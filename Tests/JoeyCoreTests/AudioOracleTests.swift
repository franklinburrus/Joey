import XCTest
@testable import JoeyCore

final class AudioOracleTests: XCTestCase {
    private func fixture(rate: Int = 48_000, gap: Int = -16, origin: Double = 0) async throws -> (URL, SourceRecord, [Float]) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-audio-oracle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let reference = directory.appendingPathComponent("untimed.f32")
        let timed = directory.appendingPathComponent("timed.nut")
        let originTicks = Int((origin * Double(rate)).rounded())
        let graph = "[0:a]asplit=2[reference][timed];"
            + "[timed]asetpts=PTS+\(originTicks)+if(gte(N\\,2048)\\,\(gap)\\,0)[clock]"
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-threads", "1",
            "-filter_threads", "1", "-filter_complex_threads", "1", "-f", "lavfi", "-i",
            "aevalsrc=0.2*sin(2*PI*1700*t)|0.2*sin(2*PI*2300*t):s=\(rate):d=0.2",
            "-filter_complex", graph, "-map", "[reference]", "-c:a", "pcm_f32le", "-f", "f32le", reference.path,
            "-map", "[clock]", "-c:a", "pcm_f32le", "-f", "nut", timed.path])
        let probe = try await Media.probe(timed)
        let source = SourceRecord(id: "synthetic-packet-clock", owner: .taxstone, title: "Packet clock",
            path: timed.path, bytes: Int64(try Data(contentsOf: timed).count), sha256: try Integrity.sha256(timed),
            duration: 0.2 + Double(max(0, gap)) / Double(rate), width: 0, height: 0, fps: 0,
            hasAudio: true, kind: .audio, streams: probe.streams, authorizationBasis: "Generated test media",
            classificationEvidence: "Synthetic PCM and explicitly defined packet timestamps")
        return (directory, source, try AudioPresentation.samples(reference))
    }

    private func expected(_ native: [Float], rate: Int, directory: URL) async throws -> [Float] {
        let raw = directory.appendingPathComponent("manual-timeline.f32")
        try native.withUnsafeBufferPointer { try Data(buffer: $0).write(to: raw) }
        let output = directory.appendingPathComponent("manual-12000.f32")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1",
            "-f", "f32le", "-ar", String(rate), "-ac", "2", "-i", raw.path,
            "-ar", "12000", "-ac", "2", "-f", "f32le", output.path])
        return try AudioPresentation.samples(output)
    }

    private func assertPCM(_ actual: [Float], equals expected: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        let changes = zip(actual, expected).enumerated().filter { abs($0.element.0 - $0.element.1) > 0.000001 }
        XCTAssertTrue(changes.isEmpty,
            "Independent PCM differs at \(changes.first?.offset ?? -1); changed samples \(changes.count)", file: file, line: line)
    }

    func testNativePacketOverlapIsPlacedBeforeResampling() async throws {
        let (directory, source, original) = try await fixture()
        // The later packet starts sixteen native samples early. Preserve the
        // established overwrite policy by removing the previous packet's last
        // sixteen samples, then leave the final sixteen timeline samples silent.
        let manual = Array(original.prefix(2_032 * 2)) + Array(original.dropFirst(2_048 * 2))
            + [Float](repeating: 0, count: 16 * 2)
        let reference = try await expected(manual, rate: 48_000, directory: directory)
        let actual = try await Media.sourceTimelineAudio(source: source, intervals: [Interval(0, 0.2)], channels: 2, work: directory)
        assertPCM(actual, equals: reference)
    }

    func testNativePacketGapAndMultipleIntervalsPreserveExactTimeline() async throws {
        let (directory, source, original) = try await fixture(gap: 16)
        let timeline = Array(original.prefix(2_048 * 2)) + [Float](repeating: 0, count: 16 * 2)
            + Array(original.dropFirst(2_048 * 2))
        // Select exact native sample ranges independently of the oracle's
        // packet reader and renderer filters, then resample the assembled PCM.
        let manual = Array(timeline[0..<(3_840 * 2)]) + Array(timeline[(5_760 * 2)..<(9_600 * 2)])
        let reference = try await expected(manual, rate: 48_000, directory: directory)
        let actual = try await Media.sourceTimelineAudio(source: source,
            intervals: [Interval(0, 0.08), Interval(0.12, 0.2)], channels: 2, work: directory)
        assertPCM(actual, equals: reference)
    }

    func testMissingNativeRateUsesProbeAndPreserves44100OriginAndEOF() async throws {
        let (directory, originalSource, original) = try await fixture(rate: 44_100, gap: 0, origin: 3)
        var source = originalSource
        let audio = try XCTUnwrap(source.streams.firstIndex(where: { $0.codec_type == "audio" }))
        XCTAssertEqual(source.streams[audio].sample_rate, "44100")
        XCTAssertEqual(Double(source.streams[audio].start_time ?? ""), 3)
        source.streams[audio].sample_rate = nil
        let manual = Array(original.dropFirst(2_205 * 2)) + [Float](repeating: 0, count: 2_205 * 2)
        let reference = try await expected(manual, rate: 44_100, directory: directory)
        let actual = try await Media.sourceTimelineAudio(source: source,
            intervals: [Interval(0.05, 0.25)], channels: 2, work: directory)
        assertPCM(actual, equals: reference)
    }

    func testNativeReferenceRetainsTypedStorageFailure() async throws {
        let (directory, source, _) = try await fixture()
        do {
            _ = try await StorageManager.$capacityOverride.withValue({ 0 }) {
                try await Media.sourceTimelineAudio(source: source, intervals: [Interval(0, 0.2)], channels: 2, work: directory)
            }
            XCTFail("Insufficient reference working capacity must remain a typed storage block")
        } catch { XCTAssertTrue(error is StorageBlocked, error.localizedDescription) }
    }

    func testCancelledReferenceDoesNotStartHelpersOrWriteScratch() async throws {
        let (directory, source, _) = try await fixture()
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Media.sourceTimelineAudio(source: source, intervals: [Interval(0, 0.2)], channels: 2, work: directory)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled reference work continued")
        } catch { XCTAssertTrue(error is CancellationError, error.localizedDescription) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
    }
}
