import XCTest
@testable import JoeyCore

final class PictureTimingTests: XCTestCase {
    private func fixture(origin: Double = 0, rate: Int = 30, millisecondClock: Bool = true,
                         videoSeconds: Int = 4, audioSeconds: Int? = nil) async throws -> (URL, SourceRecord, SharedProfile) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-picture-clock-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let pixels = directory.appendingPathComponent("source.gray")
        var frames = Data()
        // Every neighboring frame differs by at least 100 gray levels. The
        // original's 33/34 ms PTS pattern matches a millisecond video clock;
        // no Joey render or reference helper constructs these timestamps.
        for index in 0..<(rate * videoSeconds) {
            frames.append(Data(repeating: [UInt8(16), 125, 235][index % 3], count: 160 * 90))
        }
        try frames.write(to: pixels)
        let input = directory.appendingPathComponent("source.nut")
        var arguments = ["-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1",
            "-f", "rawvideo", "-pixel_format", "gray", "-video_size", "160x90", "-framerate", String(rate), "-i", pixels.path]
        if let audioSeconds {
            arguments += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono:d=\(audioSeconds)", "-c:a", "pcm_s16le"]
        }
        arguments += [
            "-vf", "settb=1/90000,setpts=" + (millisecondClock ? "floor(N*1000/\(rate))*90" : "N*90000/\(rate)") + "+\(origin)/TB",
            "-c:v", "ffv1", "-threads", "1", "-enc_time_base", "1/90000", "-fps_mode", "passthrough", input.path]
        _ = try await Processes.run("ffmpeg", arguments)
        let source = try await Media.inspect(input, request: Fixtures.request(dir: directory, path: input.path))
        return (directory, source, try Fixtures.landscapeProfile(dir: directory))
    }

    private func render(_ fixture: (URL, SourceRecord, SharedProfile), intervals: [Interval]) async throws -> (URL, ClipRecord, RenderReceipt) {
        let (directory, source, profile) = fixture
        let clip = ClipRecord(id: 1, title: "Picture clock", intervals: intervals, filename: "clip.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source: source, clip: clip, profile: profile, artwork: nil, work: directory, output: output)
        return (output, clip, receipt)
    }

    private func frame(_ url: URL, at time: Double, crop: Bool) async throws -> Data {
        let result = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1",
            "-ss", String(time), "-i", url.path, "-frames:v", "1", "-vf",
            (crop ? "crop=160:90:(iw-160)/2:(ih-90)/2," : "") + "scale=160:90,format=gray",
            "-an", "-threads", "1", "-f", "rawvideo", "-"])
        XCTAssertEqual(result.stdout.count, 160 * 90)
        return result.stdout
    }

    func testFractionalCutUsesTimestampSelectedFrameInsteadOfForwardSeekNeighbor() async throws {
        let fixture = try await fixture()
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0.78, 2.78)])
        // Output frame 6 at 0.2 s represents source frame 29 at 0.966 s.
        // Seeking directly to the ideal 0.98 s instead returns frame 30 at
        // 1.0 s. This is an observable reference error, not encoder noise.
        let actual = try await frame(output, at: 0.2, crop: true)
        let next = try await frame(URL(fileURLWithPath: fixture.1.path), at: 0.98, crop: false)
        let mean = zip(actual, next).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(actual.count)
        XCTAssertGreaterThan(mean, 16, "The fixture must expose the wrong neighboring frame without changing the fidelity threshold")
        _ = try await Media.validateSourcePictureTiming(output: output, source: fixture.1, clip: clip,
            profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
    }

    func testTimestampOracleRejectsOneFrameShiftEvenWhenNeighborWouldMatch() async throws {
        let fixture = try await fixture()
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0.78, 2.78)])
        let shifted = fixture.0.appendingPathComponent("shifted.mp4")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1",
            "-i", output.path, "-vf", "trim=start_frame=1,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=0.033333334",
            "-an", "-c:v", "libx264", "-threads", "1", "-preset", "ultrafast", "-crf", "18", "-t", "2", shifted.path])
        do {
            _ = try await Media.validateSourcePictureTiming(output: shifted, source: fixture.1, clip: clip,
                profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
            XCTFail("A timestamp oracle must reject shifted media rather than choosing whichever neighboring image matches")
        } catch { XCTAssertTrue(error.localizedDescription.contains("picture timeline"), error.localizedDescription) }
    }

    func testNonzeroOriginAndMultipleRetainedIntervalsUseTheirOriginalFrames() async throws {
        let fixture = try await fixture(origin: 5)
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0.78, 1.78), Interval(2.78, 3.78)])
        _ = try await Media.validateSourcePictureTiming(output: output, source: fixture.1, clip: clip,
            profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
    }

    func testSixtyFPSHalfFrameTiesUseTheLastFrameAssignedToEachOutputTick() async throws {
        let fixture = try await fixture(rate: 60, millisecondClock: false)
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(1, 3)])
        _ = try await Media.validateSourcePictureTiming(output: output, source: fixture.1, clip: clip,
            profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
    }

    func testEarlyVideoEndBecomesBlackWhileSourceAudioContinues() async throws {
        let fixture = try await fixture(videoSeconds: 2, audioSeconds: 4)
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0, 4)])
        let ending = try await frame(output, at: 3.6, crop: true)
        XCTAssertLessThan(ending.reduce(0.0) { $0 + Double($1) } / Double(ending.count), 1,
            "The renderer must preserve absent picture time, not freeze the final source image")
        _ = try await Media.validateSourcePictureTiming(output: output, source: fixture.1, clip: clip,
            profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
    }

    func testMissingLiveAndCachedVideoDurationUsesActualEarlyEnding() async throws {
        let fixture = try await fixture(videoSeconds: 2, audioSeconds: 4)
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0, 4)])
        let live = try await Media.probe(URL(fileURLWithPath: fixture.1.path))
        XCTAssertNil(live.video?.duration, "NUT must exercise missing live video-duration metadata")
        var legacySource = fixture.1
        let index = try XCTUnwrap(legacySource.streams.firstIndex { $0.codec_type == "video" })
        legacySource.streams[index].duration = nil
        _ = try await Media.validateSourcePictureTiming(output: output, source: legacySource, clip: clip,
            profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
        XCTAssertNil(legacySource.streams[index].duration, "Validation must not rewrite the saved source record")
    }

    func testMissingVideoDurationStillRejectsInventedFrozenTail() async throws {
        let fixture = try await fixture(videoSeconds: 2, audioSeconds: 4)
        let (output, clip, receipt) = try await render(fixture, intervals: [Interval(0, 4)])
        let live = try await Media.probe(URL(fileURLWithPath: fixture.1.path))
        XCTAssertNil(live.video?.duration)
        var legacySource = fixture.1
        let index = try XCTUnwrap(legacySource.streams.firstIndex { $0.codec_type == "video" })
        legacySource.streams[index].duration = nil
        let frozen = fixture.0.appendingPathComponent("frozen-tail.mp4")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-threads", "1", "-filter_threads", "1",
            "-i", output.path, "-vf", "trim=end=2,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=2",
            "-map", "0:v:0", "-map", "0:a:0", "-c:v", "libx264", "-threads", "1", "-preset", "ultrafast",
            "-crf", "18", "-c:a", "copy", "-t", "4", frozen.path])
        do {
            _ = try await Media.validateSourcePictureTiming(output: frozen, source: legacySource, clip: clip,
                profile: fixture.2.outputProfile(for: .nativeVideo), render: receipt)
            XCTFail("A longer audio stream must not authorize frozen video beyond the original video EOF")
        } catch { XCTAssertTrue(error.localizedDescription.contains("picture timeline"), error.localizedDescription) }
    }
}
