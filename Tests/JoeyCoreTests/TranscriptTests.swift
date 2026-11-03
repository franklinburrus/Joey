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
        import argparse, hashlib, json, pathlib, wave
        p = argparse.ArgumentParser()
        for name in ['source', 'source-id', 'output', 'model-dir', 'cpu-threads', 'language']:
            p.add_argument('--' + name)
        a = p.parse_args()
        root = pathlib.Path(__file__).parent
        if pathlib.Path(a.output).exists():
            raise SystemExit(0)
        with (root / 'helper-calls.txt').open('a') as f:
            f.write(a.source + '\n')
        source = pathlib.Path(a.source)
        with wave.open(str(source)) as w:
            duration = w.getnframes() / w.getframerate()
        if duration > 30.001:
            raise SystemExit('A full-source inference retry is prohibited by this fixture')
        end = duration + 1 if (root / 'invalid-repair').exists() else 2.0
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
