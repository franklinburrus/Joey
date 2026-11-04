import XCTest
@testable import JoeyCore

final class AACEncodingTests: XCTestCase {
    private struct PacketProbe: Decodable {
        struct Stream: Decodable { var duration_ts: Int64; var time_base: String }
        struct Packet: Decodable {
            struct SideData: Decodable, Equatable {
                var side_data_type: String
                var skip_samples: Int?
                var discard_padding: Int?
                var skip_reason: Int?
                var discard_reason: Int?
            }
            var pts: Int64
            var dts: Int64
            var duration: Int64
            var size: String
            var data_hash: String
            var side_data_list: [SideData]?
        }
        var streams: [Stream]
        var packets: [Packet]
    }

    private func packetProbe(_ url: URL) async throws -> PacketProbe {
        let result = try await Processes.run("ffprobe", ["-v", "error", "-show_streams", "-show_packets",
            "-show_data_hash", "sha256", "-of", "json", url.path])
        return try JSONDecoder().decode(PacketProbe.self, from: result.stdout)
    }

    private func assertEncodedOutput(channels: Int, nativeVideo: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-aac-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent(nativeVideo ? "source.mov" : "source.wav")
        let tones = (0..<channels).map { channel in
            "0.1*(1+0.4*sin(2*PI*4*t))*(sin(2*PI*\(310 + channel * 170)*t)+0.3*sin(2*PI*\(1300 + channel * 400)*t))"
        }.joined(separator: "|")
        var arguments = ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
                         "aevalsrc=\(tones):s=44100:d=4:c=\(channels == 1 ? "mono" : "stereo")"]
        if nativeVideo {
            arguments += ["-f", "lavfi", "-i", "testsrc2=s=160x90:r=30:d=4",
                          "-c:v", "libx264", "-pix_fmt", "yuv420p"]
        }
        arguments += ["-c:a", "pcm_s16le", sourceURL.path]
        _ = try await Processes.run("ffmpeg", arguments)
        var request = try Fixtures.request(dir: directory, path: sourceURL.path)
        request.owner = .taxstone
        let source = try await Media.inspect(sourceURL, request: request)
        XCTAssertEqual(source.kind, nativeVideo ? .nativeVideo : .audio)
        XCTAssertEqual(source.streams.first(where: { $0.codec_type == "audio" })?.sample_rate, "44100")

        var artwork: Artwork?
        if !nativeVideo {
            let image = directory.appendingPathComponent("art.png")
            _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=s=300x300", "-frames:v", "1", image.path])
            artwork = Artwork(owner: .taxstone, sourceID: source.id, driveID: "synthetic-aac-art",
                file: EvidenceFile(path: image.path, sha256: try Integrity.sha256(image), basis: "Synthetic test artwork"))
        }
        // A fractional cut checks encoder priming and the final partial QA
        // window, while the 44.1 kHz source exercises the required 48 kHz fit.
        let clip = ClipRecord(id: 1, title: "AAC contract", intervals: [Interval(0.25, 3.5)], filename: "clip.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source: source, clip: clip, profile: request.profile,
            artwork: artwork, work: directory, output: output)
        let probe = try await Media.probe(output)
        let audio = try XCTUnwrap(probe.audio)
        XCTAssertEqual(audio.codec_name, "aac")
        XCTAssertEqual(audio.profile, "LC")
        XCTAssertEqual(audio.sample_rate, "48000")
        XCTAssertEqual(audio.channels, channels)
        let bitrate = try XCTUnwrap(Int(audio.bit_rate ?? ""))
        XCTAssertGreaterThan(bitrate, 0)
        XCTAssertLessThan(bitrate, 128_000, "Measured output must remain strictly below the shared upload limit")
        XCTAssertEqual(probe.duration, clip.expectedDuration, accuracy: 0.075)
        let qa = try await Media.validate(output: output, source: source, clip: clip, profile: request.profile,
            render: receipt, work: directory)
        XCTAssertTrue(qa.passed)
        XCTAssertNotNil(qa.checks["complete_decode"])
        XCTAssertNotNil(qa.checks["audio_fidelity_sync"])
        XCTAssertNotNil(qa.checks[nativeVideo ? "source_picture_timeline" : "waveform"])
    }

    func testNativeAACPreservesMonoAndStereoThroughCompleteQA() async throws {
        for channels in [1, 2] {
            try await assertEncodedOutput(channels: channels, nativeVideo: true)
        }
    }

    func testAudioTemplateAACPreservesMonoAndStereoAndFinalWaveform() async throws {
        for channels in [1, 2] {
            try await assertEncodedOutput(channels: channels, nativeVideo: false)
        }
    }

    func testShortNativeAndVaryingAudioTemplateKeepExactLimitAndFinalWaveformPCM() async throws {
        for nativeVideo in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-aac-ending-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let input = directory.appendingPathComponent(nativeVideo ? "source.mov" : "source.wav")
            var arguments = ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
                "aevalsrc=if(lt(t\\,0.6)\\,0\\,0.1*sin(2*PI*500*t)):s=48000:d=2"]
            if nativeVideo {
                arguments += ["-f", "lavfi", "-i", "testsrc2=s=160x90:r=30:d=2",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p"]
            }
            arguments += ["-c:a", "pcm_s16le", input.path]
            _ = try await Processes.run("ffmpeg", arguments)
            var request = try Fixtures.request(dir: directory, path: input.path)
            request.owner = .taxstone
            request.profile.x!.maxDuration = 1.2
            let source = try await Media.inspect(input, request: request)
            var artwork: Artwork?
            if !nativeVideo {
                let image = directory.appendingPathComponent("art.png")
                _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
                    "testsrc2=s=300x300", "-frames:v", "1", image.path])
                artwork = Artwork(owner: .taxstone, sourceID: source.id, driveID: "synthetic-short-aac-art",
                    file: EvidenceFile(path: image.path, sha256: try Integrity.sha256(image), basis: "Synthetic test artwork"))
            }
            let clip = ClipRecord(id: 1, title: "Exact AAC ending", intervals: [Interval(0, 1.2)], filename: "clip.mp4")
            let output = directory.appendingPathComponent(clip.filename)
            let receipt = try await Media.render(source: source, clip: clip, profile: request.profile,
                artwork: artwork, work: directory, output: output)
            let probe = try await Media.probe(output)
            XCTAssertLessThanOrEqual(probe.duration, 1.2, "Codec padding must not extend the verified hard duration limit")
            let qa = try await Media.validate(output: output, source: source, clip: clip, profile: request.profile,
                render: receipt, work: directory)
            XCTAssertTrue(qa.passed)
            if !nativeVideo {
                let expected = try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(receipt.waveformPCM)))
                let final = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
                    "-vn", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"])
                XCTAssertEqual(final.stdout, expected, "Waveform input must match the actual final audio after muxing")
            }
        }
    }

    func testIntegerEndingPreservesRetainedPacketsPrimingAndEveryPlannedSample() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-aac-packets-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("original-encode.m4a")
        var unbounded = Media.audioEncodingArguments(channels: 1, duration: 2)
        let position = try XCTUnwrap(unbounded.firstIndex(of: "-bsf:a"))
        unbounded.removeSubrange(position...position + 1)
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
            "aevalsrc=0.1*sin(2*PI*500*t):s=48000:d=2", "-af", Media.audioEncodingFormat(channels: 1)]
            + unbounded + [baseline.path])
        let original = try await packetProbe(baseline)
        let originalPCM = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", baseline.path,
            "-vn", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"])
        XCTAssertLessThan(try XCTUnwrap(original.packets.first).pts, 0, "The fixture must contain genuine encoder priming")
        XCTAssertGreaterThan(try XCTUnwrap(original.packets.first?.side_data_list?.first?.skip_samples), 0)

        // 1.236 seconds coincides with a real packet PTS. Raising it by one ULP
        // must not retain that wholly post-ending packet or change sample count.
        for (index, duration) in [1.2, Double(1.236).nextUp].enumerated() {
            let ending = Int64((duration * 48_000).rounded())
            let encoded = Media.audioEncodingArguments(channels: 1, duration: duration)
            let filterPosition = try XCTUnwrap(encoded.firstIndex(of: "-bsf:a"))
            let output = directory.appendingPathComponent("normalized-\(index).m4a")
            // Copy existing packets so the only operation under test is the
            // production packet boundary filter, not a second codec invocation.
            _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", baseline.path,
                "-map", "0:a:0", "-c:a", "copy", "-bsf:a", encoded[filterPosition + 1], output.path])
            let normalized = try await packetProbe(output)
            XCTAssertEqual(normalized.streams.first?.time_base, "1/48000")
            XCTAssertEqual(normalized.streams.first?.duration_ts, ending)
            let retained = original.packets.filter { $0.pts < ending }
            XCTAssertEqual(normalized.packets.count, retained.count)
            for (before, after) in zip(retained, normalized.packets) {
                XCTAssertEqual(after.pts, before.pts)
                XCTAssertEqual(after.dts, before.dts)
                XCTAssertEqual(after.data_hash, before.data_hash)
                XCTAssertEqual(after.size, before.size)
                XCTAssertEqual(after.side_data_list, before.side_data_list)
                XCTAssertEqual(after.duration, min(before.duration, ending - before.pts))
            }
            let finalPCM = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-i", output.path,
                "-vn", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"])
            let plannedBytes = Int(ending) * MemoryLayout<Float>.size
            XCTAssertGreaterThanOrEqual(finalPCM.stdout.count, plannedBytes)
            XCTAssertEqual(finalPCM.stdout.prefix(plannedBytes), originalPCM.stdout.prefix(plannedBytes))
        }
    }
}
