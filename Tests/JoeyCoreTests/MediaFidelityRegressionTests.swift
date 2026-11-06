import XCTest
@testable import JoeyCore

final class MediaFidelityRegressionTests: XCTestCase {
    private func fixture(size: String = "320x180", stereo: Bool = false, variableRate: Bool = false) async throws -> (URL, SourceRecord, SharedProfile, ClipRecord, RenderReceipt, URL) {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("joey-fidelity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        let input = work.appendingPathComponent("source.mov")
        let tone = "0.3*sin(2*PI*440*t)+0.1*sin(2*PI*970*t)"
        var arguments = ["-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc2=s=\(size):r=\(variableRate ? 60 : 30):d=10",
            "-f", "lavfi", "-i", "aevalsrc=\(stereo ? tone + "|" + tone : tone):s=48000:d=10"]
        if variableRate { arguments += ["-vf", #"select=not(mod(n\,2))+eq(mod(n\,5)\,0)"#, "-fps_mode", "passthrough"] }
        arguments += ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", input.path]
        _ = try await Processes.run("ffmpeg", arguments)
        let source = try await Media.inspect(input, request: Fixtures.request(dir: work, path: input.path))
        let profile = try Fixtures.landscapeProfile(dir: work)
        let clip = ClipRecord(id: 1, title: "Fidelity regression", intervals: [Interval(0, 10)], filename: "correct.mp4")
        let output = work.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source: source, clip: clip, profile: profile, artwork: nil, work: work, output: output)
        let baseline = try await Media.validate(output: output, source: source, clip: clip, profile: profile, render: receipt, work: work)
        XCTAssertTrue(baseline.passed, "The unchanged production render must pass before testing damage")
        return (work, source, profile, clip, receipt, output)
    }

    func testVariableFrameRateBaselinePassesProductionValidation() async throws {
        let (_, source, _, _, _, _) = try await fixture(variableRate: true)
        XCTAssertEqual(source.classificationProof?.decodedFrameCount, 360,
            "The 60 fps clock must retain the intended irregular 360-frame source, without resampling before QA")
    }

    func testRepeated100MillisecondDropoutsFailProductionValidation() async throws {
        let (work, source, profile, clip, receipt, output) = try await fixture()
        let damaged = work.appendingPathComponent("muted.mp4")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
            "-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy", "-af",
            #"aeval=if(between(mod(t\,1)\,0.4\,0.5)\,0\,val(0))"#]
            + Media.audioEncodingArguments(channels: 1, duration: 10) + ["-movflags", "+faststart", "-t", "10", damaged.path])
        do {
            _ = try await Media.validate(output: damaged, source: source, clip: clip, profile: profile, render: receipt, work: work)
            XCTFail("Production QA accepted repeated 100 ms omissions of audible source content")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Audio"), error.localizedDescription) }
    }

    func testOneStereoChannelRepeatedDropoutsFailProductionValidation() async throws {
        let (work, source, profile, clip, receipt, output) = try await fixture(stereo: true)
        let damaged = work.appendingPathComponent("right-muted.mp4")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
            "-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy", "-af",
            #"aeval=val(0)|if(between(mod(t\,1)\,0.4\,0.5)\,0\,val(1))"#]
            + Media.audioEncodingArguments(channels: 2, duration: 10) + ["-movflags", "+faststart", "-t", "10", damaged.path])
        do {
            _ = try await Media.validate(output: damaged, source: source, clip: clip, profile: profile, render: receipt, work: work)
            XCTFail("The unchanged stereo channel must not hide repeated omissions in the other channel")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Audio"), error.localizedDescription) }
    }

    func testOnePointFourSecondBlackoutFailsForSmallAndFullSizePictures() async throws {
        for size in ["320x180", "1920x1080"] {
            let (work, source, profile, clip, receipt, output) = try await fixture(size: size)
            let damaged = work.appendingPathComponent("blacked.mp4")
            _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
                "-map", "0:v:0", "-map", "0:a:0", "-vf",
                "drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill:enable='between(t,2.3,3.7)'",
                "-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-c:a", "copy", "-movflags", "+faststart", damaged.path])
            do {
                _ = try await Media.validate(output: damaged, source: source, clip: clip, profile: profile, render: receipt, work: work)
                XCTFail("Production QA accepted 1.4 seconds of erased \(size) source picture")
            } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("picture"), error.localizedDescription) }
        }
    }

    func testShortUnauthorizedPaddingOverlayFailsProductionValidation() async throws {
        let (work, source, profile, clip, receipt, output) = try await fixture()
        let damaged = work.appendingPathComponent("overlay.mp4")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
            "-map", "0:v:0", "-map", "0:a:0", "-vf",
            "drawbox=x=50:y=50:w=180:h=180:color=white:t=fill:enable='between(t,2.3,3.7)'",
            "-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-c:a", "copy", "-movflags", "+faststart", damaged.path])
        do {
            _ = try await Media.validate(output: damaged, source: source, clip: clip, profile: profile, render: receipt, work: work)
            XCTFail("A short unauthorized overlay in black padding must fail QA")
        } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("picture"), error.localizedDescription) }
    }
}
