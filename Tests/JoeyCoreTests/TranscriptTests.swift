import XCTest
@testable import JoeyCore

final class TranscriptTests: XCTestCase {
    private struct Fixture {
        var root: URL
        var source: SourceRecord
        var request: JobRequest
        var configuration: Configuration
        var raw: URL { root.appendingPathComponent("asr-source.json") }
        var canonical: URL { root.appendingPathComponent("transcript.json") }
        var calls: URL { root.appendingPathComponent("helper-calls.txt") }
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("original.wav")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
            "sine=frequency=440:sample_rate=16000:duration=40", "-c:a", "pcm_s16le", audio.path])
        let request = try Fixtures.request(dir: root, path: audio.path)
        let source = try await Media.inspect(audio, request: request)
        // Only inference is replaced: real extraction, measured audio, source
        // hashes, adoption, persistence and recovery run through production code.
        let helper = root.appendingPathComponent("synthetic-asr.py")
        try Data(#"""
        import argparse, hashlib, json, pathlib, time, wave
        p = argparse.ArgumentParser()
        for name in ['source', 'source-id', 'output', 'model-dir', 'cpu-threads', 'language']:
            p.add_argument('--' + name)
        a = p.parse_args()
        root = pathlib.Path(__file__).parent
        if pathlib.Path(a.output).exists():
            raise SystemExit(0)
        with (root / 'helper-calls.txt').open('a') as f:
            f.write(a.source + '\n')
        if (root / 'wait-in-helper').exists():
            time.sleep(30)
        source = pathlib.Path(a.source)
        with wave.open(str(source)) as w:
            duration = w.getnframes() / w.getframerate()
        if duration > 30.001:
            raise SystemExit('A full-source inference retry is prohibited by this fixture')
        end = duration + 1 if (root / 'invalid-repair').exists() else 2.0
        if (root / 'cross-boundary').exists():
            end = duration + 0.05
        payload = {
            'source_id': a.source_id, 'source_file': source.name,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'model': 'mlx-whisper', 'language': 'en', 'word_timestamps': True,
            'transcription_status': 'completed; ASR accuracy not independently verified',
            'segments': [{'start_seconds': 0.0, 'end_seconds': end,
                'text': 'Regenerated tail sentence.',
                'words': [{'start_seconds': 0.0, 'end_seconds': end,
                           'text': ' Regenerated tail sentence.'}]}]
        }
        if (root / 'unaligned-repair').exists():
            payload['segments'][0]['words'] = []
        if (root / 'invalid-word-repair').exists():
            payload['segments'][0]['words'][0]['start_seconds'] = -1
        if (root / 'wrong-repair-source').exists():
            payload['source_id'] = 'unrelated-excerpt'
        pathlib.Path(a.output).write_text(json.dumps(payload))
        """#.utf8).write(to: helper)
        var config = Configuration()
        config.pythonPath = "/usr/bin/python3"
        config.transcriptionScript = helper.path
        config.modelPath = root.path
        let result = Fixture(root: root, source: source, request: request, configuration: config)
        try saveRaw(result, segments: [
            segment(0, 8, "Preserve this prefix exactly."),
            segment(10, 12, "Previous tail transcription."),
            segment(39.3, 40.72, "Unaligned final engine result.", words: false),
            segment(39.3, 39.6, "Final word.")
        ])
        return result
    }

    private func segment(_ start: Double, _ end: Double, _ text: String, words: Bool = true) -> [String: Any] {
        ["start_seconds": start, "end_seconds": end, "text": text,
         "words": words ? [["start_seconds": start, "end_seconds": end, "text": text]] : []]
    }

    private func saveRaw(_ fixture: Fixture, segments: [[String: Any]], sourceID: String? = nil) throws {
        let object: [String: Any] = ["source_id": sourceID ?? fixture.source.id,
            "source_sha256": fixture.source.sha256, "source_file": "original.wav",
            "model": "mlx-whisper", "language": "en", "word_timestamps": true,
            "transcription_status": "completed; ASR accuracy not independently verified", "segments": segments]
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: fixture.raw)
    }

    private func adopt(_ fixture: Fixture) async throws -> Transcript? {
        try await Acquisition.transcript(source: fixture.source, request: fixture.request,
            configuration: fixture.configuration, directory: fixture.root)
    }

    private func interiorSegments() -> [[String: Any]] {
        [segment(0, 3, "First preserved prefix."),
         segment(3.1, 4, "Second preserved prefix."),
         segment(4.06, 7.9, "Left context."),
         segment(7.92, 8.7, "More left context."),
         segment(9.1, 10.5, "Earlier aligned speech."),
         segment(11, 12, "Continuing speech."),
         segment(12.38, 12.6, "Nearby repeated words."),
         segment(23.1, 24.74, "Displaced aligned speech."),
         segment(12.38, 13, "Uncertain repeated words.", words: false),
         segment(24.74, 25.66, "Right context."),
         segment(32.22, 34.12, "First preserved suffix."),
         segment(35.76, 37.76, "Second preserved suffix."),
         segment(38.46, 39.8, "Last preserved suffix.")]
    }

    func testSingleWordlessInteriorFaultRegeneratesBoundedAudioAndPreservesBothSides() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: interiorSegments())
        let raw = try Data(contentsOf: f.raw)
        let result = try await adopt(f)
        let transcript = try XCTUnwrap(result)
        XCTAssertEqual(transcript.segments, [
            TranscriptSegment(start: 0, end: 3, text: "First preserved prefix."),
            TranscriptSegment(start: 3.1, end: 4, text: "Second preserved prefix."),
            TranscriptSegment(start: 4.06, end: 6.06, text: "Regenerated tail sentence."),
            TranscriptSegment(start: 32.22, end: 34.12, text: "First preserved suffix."),
            TranscriptSegment(start: 35.76, end: 37.76, text: "Second preserved suffix."),
            TranscriptSegment(start: 38.46, end: 39.8, text: "Last preserved suffix.")
        ])
        XCTAssertEqual(try Data(contentsOf: f.raw), raw)
        XCTAssertEqual(transcript.sourceSHA256, f.source.sha256)
        XCTAssertEqual(transcript.duration, f.source.duration)
        let excerpt = f.root.appendingPathComponent("transcript-repair/source-window.wav")
        let measured = try await Media.probe(excerpt)
        XCTAssertEqual(measured.duration, 28.16, accuracy: 0.001)
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            f.root.appendingPathComponent("transcript-repair.json"))) as? [String: Any])
        XCTAssertEqual(proof["tailStart"] as? Double, 4.06)
        XCTAssertEqual(proof["windowEnd"] as? Double, 32.22)
        XCTAssertEqual(try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testInteriorRepairRecoversCanonicalWriteAndReopensWithoutInferenceOrEvidenceChanges() async throws {
        var f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: interiorSegments())
        let accepted = try await adopt(f)
        let acceptedBytes = try Data(contentsOf: f.canonical)
        let calls = try Data(contentsOf: f.calls)
        let receipt = f.root.appendingPathComponent("transcript-repair.json")
        let receiptBytes = try Data(contentsOf: receipt)
        try FileManager.default.removeItem(at: f.canonical)
        f.configuration = Configuration()
        let recovered = try await adopt(f)
        XCTAssertEqual(recovered, accepted)
        XCTAssertEqual(try Data(contentsOf: f.canonical), acceptedBytes)
        let reopened = try await adopt(f)
        XCTAssertEqual(reopened, accepted)
        XCTAssertEqual(try Data(contentsOf: receipt), receiptBytes)
        XCTAssertEqual(try Data(contentsOf: f.calls), calls)
    }

    func testInteriorRecoveryRejectsUnsupportedOrAdditionalFaultsBeforeInference() async throws {
        let cases = ["imported", "aligned-fault", "two-faults", "source-overrun", "another-wordless",
                     "unsupported-engine", "wrong-source", "no-word-timestamps", "missing-words", "no-safe-window"]
        for name in cases {
            var f = try await fixture()
            defer { try? FileManager.default.removeItem(at: f.root) }
            var segments = interiorSegments()
            switch name {
            case "aligned-fault": segments[8] = segment(12.38, 13, "Aligned backward speech.")
            case "two-faults": segments.insert(segment(2.5, 2.8, "Another backward result.", words: false), at: 2)
            case "source-overrun": segments[12] = segment(38.46, 41, "Additional duration fault.")
            case "another-wordless": segments[0] = segment(0, 3, "Unaligned prefix.", words: false)
            case "missing-words": segments[8].removeValue(forKey: "words")
            case "no-safe-window": segments = [segment(0, 35, "Crossing every bounded left boundary."),
                segment(35, 36, "Aligned speech."), segment(34.9, 35, "Backward result.", words: false),
                segment(36, 39, "Suffix.")]
            default: break
            }
            try saveRaw(f, segments: segments)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.raw)) as? [String: Any])
            if name == "unsupported-engine" { raw["model"] = "unsupported-asr" }
            if name == "wrong-source" { raw["source_sha256"] = String(repeating: "0", count: 64) }
            if name == "no-word-timestamps" { raw["word_timestamps"] = false }
            try JSONSerialization.data(withJSONObject: raw).write(to: f.raw)
            if name == "imported" { f.request.transcriptPath = f.raw.path }
            let original = try Data(contentsOf: f.raw)
            do { _ = try await adopt(f); XCTFail("Unsupported recovery accepted: \(name)") }
            catch { XCTAssertTrue(error.localizedDescription.contains("transcript"), "\(name): \(error)") }
            XCTAssertEqual(try Data(contentsOf: f.raw), original, name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path), name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path), name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("transcript-repair").path), name)
        }
    }

    func testInteriorEligibilityDoesNotReclassifyExistingWordToSegmentOverhangs() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var segments = interiorSegments()
        segments[0]["words"] = [["start_seconds": 0.0, "end_seconds": 3.2, "text": "Preserved timing."]]
        try saveRaw(f, segments: segments)
        let original = try Data(contentsOf: f.raw)
        let result = try await adopt(f)
        XCTAssertEqual(result?.segments.first, TranscriptSegment(start: 0, end: 3, text: "First preserved prefix."))
        XCTAssertEqual(try Data(contentsOf: f.raw), original)
    }

    func testInteriorRepairBindsEvidenceAndRederivesBoundariesFromOriginalASR() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: interiorSegments())
        _ = try await adopt(f)
        let calls = try Data(contentsOf: f.calls)
        let protected = [URL(fileURLWithPath: f.source.path), f.raw, f.canonical,
            f.root.appendingPathComponent("transcript-repair/source-window.wav"),
            f.root.appendingPathComponent("transcript-repair/asr-window.json")]
        for file in protected {
            let original = try Data(contentsOf: file)
            try (original + Data("changed".utf8)).write(to: file)
            do { _ = try await adopt(f); XCTFail("Changed evidence reused: \(file.lastPathComponent)") }
            catch { XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription) }
            try original.write(to: file)
        }
        let receipt = f.root.appendingPathComponent("transcript-repair.json")
        let originalProof = try Data(contentsOf: receipt)
        var proof = try XCTUnwrap(JSONSerialization.jsonObject(with: originalProof) as? [String: Any])
        // Bounds and duration remain locally consistent, but no longer match
        // the deterministic boundaries derived from the retained original ASR.
        proof["tailStart"] = 4.07
        proof["windowEnd"] = 32.23
        try JSONSerialization.data(withJSONObject: proof).write(to: receipt)
        do { _ = try await adopt(f); XCTFail("Changed interval bypassed original-ASR boundary checks") }
        catch { XCTAssertTrue(error.localizedDescription.contains("boundary"), error.localizedDescription) }
        try originalProof.write(to: receipt)
        XCTAssertEqual(try Data(contentsOf: f.calls), calls)
    }

    func testInvalidRegeneratedInteriorResultsRemainPreservedWithoutInferenceLoops() async throws {
        for marker in ["invalid-repair", "cross-boundary", "unaligned-repair", "invalid-word-repair", "wrong-repair-source"] {
            let f = try await fixture()
            defer { try? FileManager.default.removeItem(at: f.root) }
            try saveRaw(f, segments: interiorSegments())
            let raw = try Data(contentsOf: f.raw)
            try Data().write(to: f.root.appendingPathComponent(marker))
            let generated = f.root.appendingPathComponent("transcript-repair/asr-window.json")
            var retained: Data?
            for _ in 0..<2 {
                do { _ = try await adopt(f); XCTFail("Invalid regenerated interior accepted: \(marker)") }
                catch { XCTAssertTrue(error.localizedDescription.contains("preserved"), error.localizedDescription) }
                let current = try Data(contentsOf: generated)
                if let retained { XCTAssertEqual(current, retained, marker) } else { retained = current }
            }
            XCTAssertEqual(try Data(contentsOf: f.raw), raw, marker)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path), marker)
            XCTAssertEqual(try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n").count, 1, marker)
        }
    }

    func testInteriorStorageBlockRetainsItsTypedRecoverySignal() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: interiorSegments())
        let original = try Data(contentsOf: f.raw)
        do {
            _ = try await StorageManager.$processingRoot.withValue(f.root) {
                try await StorageManager.$capacityOverride.withValue({ 0 }) { try await adopt(f) }
            }
            XCTFail("Interior recovery ignored storage exhaustion")
        } catch let blocked as StorageBlocked {
            XCTAssertEqual(blocked.available, 0)
            XCTAssertGreaterThan(blocked.required, 0)
        } catch { XCTFail("Storage recovery signal was replaced: \(error)") }
        XCTAssertEqual(try Data(contentsOf: f.raw), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
    }

    func testCancellingInteriorHelperPropagatesCancellationAndPreservesOriginalASR() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: interiorSegments())
        let original = try Data(contentsOf: f.raw)
        try Data().write(to: f.root.appendingPathComponent("wait-in-helper"))
        let task = Task { try await self.adopt(f) }
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: f.calls.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = FileManager.default.fileExists(atPath: f.calls.path)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled interior helper returned acceptance") }
        catch is CancellationError {} catch { XCTFail("Cancellation was replaced: \(error)") }
        XCTAssertTrue(started, "The real supervised helper must start before cancellation")
        XCTAssertEqual(try Data(contentsOf: f.raw), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("transcript-repair.json").path))
    }

    func testLegacyTailReceiptAndIdentitySurviveReuseAndInterruptedCanonicalWriteUnchanged() async throws {
        var f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let accepted = try await adopt(f)
        XCTAssertEqual(accepted?.engine, "mlx-whisper; bounded local tail retranscription")
        let generated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            f.root.appendingPathComponent("transcript-repair/asr-tail.json"))) as? [String: Any])
        XCTAssertEqual(generated["source_id"] as? String, f.source.id + ":transcript-tail:10.0")
        let receipt = f.root.appendingPathComponent("transcript-repair.json")
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any])
        XCTAssertEqual(Set(proof.keys), Set(["sourceID", "sourceSHA256", "sourceDuration", "originalASRSHA256",
            "tailStart", "tailDuration", "tailSHA256", "regeneratedASRSHA256", "transcriptSHA256"]))
        let legacyBytes = try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys])
        try legacyBytes.write(to: receipt)
        let calls = try Data(contentsOf: f.calls)
        let canonical = try Data(contentsOf: f.canonical)
        f.configuration = Configuration()
        let reused = try await adopt(f)
        XCTAssertEqual(reused, accepted)
        XCTAssertEqual(try Data(contentsOf: receipt), legacyBytes)
        try FileManager.default.removeItem(at: f.canonical)
        let recovered = try await adopt(f)
        XCTAssertEqual(recovered, accepted)
        XCTAssertEqual(try Data(contentsOf: f.canonical), canonical)
        XCTAssertEqual(try Data(contentsOf: receipt), legacyBytes)
        XCTAssertEqual(try Data(contentsOf: f.calls), calls)
    }

    func testInvalidLocalTailRegeneratesOnlyBoundedAudioAndPreservesPrefixAndRawResult() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let raw = try Data(contentsOf: f.raw)
        let result = try await adopt(f)
        let transcript = try XCTUnwrap(result)
        XCTAssertEqual(transcript.segments, [
            TranscriptSegment(start: 0, end: 8, text: "Preserve this prefix exactly."),
            TranscriptSegment(start: 10, end: 12, text: "Regenerated tail sentence.")
        ])
        XCTAssertEqual(transcript.sourceSHA256, f.source.sha256)
        XCTAssertEqual(transcript.duration, 40)
        XCTAssertEqual(try Data(contentsOf: f.raw), raw)
        let excerpt = f.root.appendingPathComponent("transcript-repair/source-tail.wav")
        let measured = try await Media.probe(excerpt)
        XCTAssertEqual(measured.duration, 30, accuracy: 0.001)
        XCTAssertEqual(try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n").count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("transcript-repair.json").path))
    }

    func testValidatedRepairIsReusedAfterCanonicalWriteInterruptionWithoutInference() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let accepted = try await adopt(f)
        let calls = try Data(contentsOf: f.calls)
        try FileManager.default.removeItem(at: f.canonical)
        let recovered = try await adopt(f)
        XCTAssertEqual(recovered, accepted)
        XCTAssertEqual(try Data(contentsOf: f.calls), calls)
        let acceptedBytes = try Data(contentsOf: f.canonical)
        let reused = try await adopt(f)
        XCTAssertEqual(reused, accepted)
        XCTAssertEqual(try Data(contentsOf: f.canonical), acceptedBytes)
    }

    func testRepairCannotReuseChangedSourceOrEvidence() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await adopt(f)
        let calls = try Data(contentsOf: f.calls)
        let protected = [URL(fileURLWithPath: f.source.path), f.raw, f.canonical,
            f.root.appendingPathComponent("transcript-repair/source-tail.wav"),
            f.root.appendingPathComponent("transcript-repair/asr-tail.json")]
        for file in protected {
            let original = try Data(contentsOf: file)
            try (original + Data("changed".utf8)).write(to: file)
            do { _ = try await adopt(f); XCTFail("Changed evidence reused: \(file.lastPathComponent)") }
            catch { XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription) }
            try original.write(to: file)
        }
        XCTAssertEqual(try Data(contentsOf: f.calls), calls)
    }

    func testMissingRepairReceiptCannotBypassEvidenceChecks() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await adopt(f)
        let accepted = try Data(contentsOf: f.canonical)
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("transcript-repair.json"))
        do { _ = try await adopt(f); XCTFail("Missing repair receipt bypassed accepted evidence checks") }
        catch { XCTAssertTrue(error.localizedDescription.contains("receipt"), error.localizedDescription) }
        XCTAssertEqual(try Data(contentsOf: f.canonical), accepted)
    }

    func testMidstreamAndImportedDefectsFailWithoutInferenceOrCanonicalTranscript() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: [segment(0, 8, "Prefix."), segment(9, 41, "Midstream invalid interval.")])
        do { _ = try await adopt(f); XCTFail("Midstream defect accepted") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("segment 2"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("preserved"), error.localizedDescription)
        }
        var supplied = f
        supplied.request.transcriptPath = f.raw.path
        try saveRaw(f, segments: [segment(39.3, 40.72, "Imported invalid interval.")])
        do { _ = try await adopt(supplied); XCTFail("Imported timestamps silently repaired") }
        catch { XCTAssertTrue(error.localizedDescription.contains("segment 1"), error.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
    }

    func testWrongSourceHashDoesNotInvokeRecovery() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: [segment(39.3, 40.72, "Wrong source.")], sourceID: "unrelated-source")
        do { _ = try await adopt(f); XCTFail("Wrong source accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("source"), error.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
    }

    func testValidRetainedRawTranscriptIsAdoptedWithoutAnAvailableASRHelper() async throws {
        var f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try saveRaw(f, segments: [segment(0, 8, "Existing source-bound transcript.")])
        f.configuration = Configuration()
        let result = try await adopt(f)
        XCTAssertEqual(result?.segments, [TranscriptSegment(start: 0, end: 8, text: "Existing source-bound transcript.")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.canonical.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path))
    }

    func testStorageBlockedDuringTailRecoveryRetainsItsTypedRecoverySignal() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try Data(contentsOf: f.raw)
        do {
            _ = try await StorageManager.$processingRoot.withValue(f.root) {
                try await StorageManager.$capacityOverride.withValue({ 0 }) { try await adopt(f) }
            }
            XCTFail("Tail recovery ignored storage exhaustion")
        } catch let blocked as StorageBlocked {
            XCTAssertEqual(blocked.available, 0)
            XCTAssertGreaterThan(blocked.required, 0)
        } catch { XCTFail("Storage recovery signal was replaced: \(error)") }
        XCTAssertEqual(try Data(contentsOf: f.raw), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
    }

    func testConflictingTypedSourceIdentityCannotEnterTailRecovery() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.raw)) as? [String: Any])
        payload["sourceID"] = "unrelated-source"
        payload["sourceSHA256"] = f.source.sha256
        payload["duration"] = f.source.duration
        payload["engine"] = "mlx-whisper"
        payload["segments"] = try XCTUnwrap(payload["segments"] as? [[String: Any]]).map { segment in
            var result = segment
            result["start"] = segment["start_seconds"]
            result["end"] = segment["end_seconds"]
            return result
        }
        try JSONSerialization.data(withJSONObject: payload).write(to: f.raw)
        do { _ = try await adopt(f); XCTFail("Conflicting source identity was replaced during tail recovery") }
        catch { XCTAssertTrue(error.localizedDescription.contains("source"), error.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.calls.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
    }

    func testSuppliedTranscriptRecoversFailedTailAttemptAndReopens() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try Data().write(to: f.root.appendingPathComponent("invalid-repair"))
        do { _ = try await adopt(f); XCTFail("Invalid tail unexpectedly accepted") } catch {}
        let proof = f.root.appendingPathComponent("transcript-repair.json")
        let failedEvidence = try Data(contentsOf: proof)
        let supplied = Transcript(sourceID: f.source.id, sourceSHA256: f.source.sha256, duration: 40,
            engine: "Source-bound supplied correction", segments: [TranscriptSegment(start: 0, end: 40, text: "Complete corrected source transcript.")])
        let input = f.root.appendingPathComponent("supplied-transcript.json")
        try Persistence.save(supplied, to: input)
        var corrected = f
        corrected.request.transcriptPath = input.path
        corrected.configuration = Configuration()
        let adopted = try await adopt(corrected)
        XCTAssertEqual(adopted, supplied)
        let reopened = try await adopt(corrected)
        XCTAssertEqual(reopened, supplied)
        XCTAssertEqual(try Data(contentsOf: proof), failedEvidence)
        XCTAssertEqual(try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testInvalidRegeneratedTailRemainsActionableAndDoesNotLoopInference() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try Data().write(to: f.root.appendingPathComponent("invalid-repair"))
        for _ in 0..<2 {
            do { _ = try await adopt(f); XCTFail("Invalid regenerated result accepted") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains("preserved"), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.contains("source-bound transcript"), error.localizedDescription)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.canonical.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("transcript-repair/asr-tail.json").path))
        XCTAssertEqual(try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n").count, 1)
    }
}
