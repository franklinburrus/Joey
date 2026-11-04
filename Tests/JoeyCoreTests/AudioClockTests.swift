import XCTest
@testable import JoeyCore

final class AudioClockTests: XCTestCase {
    private func assertSourcePCMAndGapPreserved(start: Double) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("joey-audio-clock-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let root = try StorageManager.canonicalRoot(temporary)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let referenceURL = root.appendingPathComponent("reference.f32")
        let actualURL = root.appendingPathComponent("actual.f32")
        let interval = Interval(start, start + 0.2)
        let sourceTicks = Int64((start * 48_000).rounded())
        let graph = "[0:a]asplit=2[reference][timed];"
            + "[timed]asetpts=PTS+\(sourceTicks)+if(gte(N\\,2048)\\,16\\,0),"
            + Media.intervalAudioFilter(interval) + "[actual]"
        _ = try await Processes.run("ffmpeg", [
            "-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1", "-filter_complex_threads", "1",
            "-f", "lavfi", "-i", "aevalsrc=0.1*sin(2*PI*7000*t)|0.1*sin(2*PI*6000*t):s=48000:d=0.2",
            "-filter_complex", graph,
            "-map", "[reference]", "-c:a", "pcm_f32le", "-f", "f32le", referenceURL.path,
            "-map", "[actual]", "-c:a", "pcm_f32le", "-f", "f32le", actualURL.path
        ])
        let reference = try AudioPresentation.samples(referenceURL)
        let actual = try AudioPresentation.samples(actualURL)
        XCTAssertEqual(reference.count, 9_600 * 2)

        // The source clock contains a known sixteen-sample gap after native
        // sample 2048. Construct the intended PCM independently of FFmpeg's
        // timestamp arithmetic and asynchronous resampler: preserve the prefix,
        // insert silence for that gap, and retain the original following data.
        let gapStart = 2_048 * 2, gapCount = 16 * 2
        let expected = Array(reference.prefix(gapStart))
            + [Float](repeating: 0, count: gapCount)
            + Array(reference[gapStart..<(reference.count - gapCount)])
        XCTAssertEqual(actual.count, expected.count, "The requested interval must retain its complete PCM length")
        let mismatches = zip(actual, expected).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertTrue(mismatches.isEmpty,
            "Source PCM or gap moved at start \(start); first changed interleaved sample \(mismatches.first?.offset ?? -1), changed samples \(mismatches.count)")
    }

    func testFractionalSecondStartPreservesNativePCMAndPacketGapExactly() async throws {
        // 1651.38 / (1/48000) evaluates slightly above its integer tick count.
        // A floating subtraction can shift later packet timestamps one tick
        // early; hard gap compensation then advances the actual audio sample.
        try await assertSourcePCMAndGapPreserved(start: 1651.38)
    }

    func testIntegerSecondStartPreservesNativePCMAndPacketGapExactly() async throws {
        try await assertSourcePCMAndGapPreserved(start: 1651)
    }
}
