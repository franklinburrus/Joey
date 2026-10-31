import XCTest
@testable import JoeyCore

final class MediaTests: XCTestCase {
    func testNativeRenderPreservesFrameAndRejectsCorruption() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let sourceURL = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=3","-f","lavfi","-i","sine=frequency=440:duration=3","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",sourceURL.path])
        let source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        let clip = ClipRecord(id:1,title:"fixture",intervals:[Interval(0.25,1.25),Interval(2,3)],filename:"clip.mp4")
        let output = dir.appendingPathComponent("clip.mp4")
        let profile = try Fixtures.profile(dir:dir)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let p = try await Media.probe(output)
        XCTAssertEqual(p.video?.width,720); XCTAssertEqual(p.video?.height,1280)
        XCTAssertEqual(p.duration,2,accuracy:0.075)
        XCTAssertEqual(render.pictureWidth,320); XCTAssertEqual(render.pictureHeight,180)
        try Data("corrupt".utf8).write(to:output)
        do { _ = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir); XCTFail("Corrupt output accepted") }
        catch { XCTAssertFalse(error is CancellationError) }
    }
    func testSilentWaveformDoesNotInventMotion() {
        let result = AudioPresentation.envelope(samples:Array(repeating:Float(0),count:4800),sampleRate:48000)
        XCTAssertTrue(result.levels.allSatisfy {$0 == 0})
        XCTAssertTrue(result.shape.allSatisfy {$0 == 0})
    }
    func testWaveformRespondsToSelectedAudio() {
        let samples = (0..<48000).map { i in i < 24000 ? Float(0) : Float(sin(Double(i)*0.05)*0.4) }
        let wave = AudioPresentation.envelope(samples:samples,sampleRate:48000)
        XCTAssertLessThan(wave.levels[5],0.001)
        XCTAssertGreaterThan(wave.levels[25],0.5)
        XCTAssertEqual(wave.shape.count,120)
    }
}

enum Fixtures {
    static func profile(dir: URL) throws -> SharedProfile {
        let p = dir.appendingPathComponent("capability-evidence.txt")
        try Data("Synthetic fixture capability; never production evidence".utf8).write(to:p)
        let proof = EvidenceFile(path:p.path,sha256:try Integrity.sha256(p),basis:"TEST ONLY")
        let x = SurfaceCapability(platform:"X",account:"fixture",surface:"fixture",checkedAt:Date().addingTimeInterval(-60),validUntil:Date().addingTimeInterval(3600),maxDuration:600,maxBytes:512_000_000,maxWidth:720,maxHeight:1280,maxFPS:30,officialURLs:["https://help.x.com/en/using-x/x-videos"],accountEvidence:proof)
        let ig = SurfaceCapability(platform:"Instagram",account:"fixture",surface:"fixture",checkedAt:x.checkedAt,validUntil:x.validUntil,maxDuration:900,maxBytes:1_000_000_000,maxWidth:1080,maxHeight:1920,maxFPS:60,officialURLs:["https://developers.facebook.com/docs/instagram-platform/content-publishing"],accountEvidence:proof)
        return try SharedProfile.select(x:x,instagram:ig)
    }
    static func request(dir: URL, path: String) throws -> JobRequest {
        JobRequest(owner:.dub,sourceID:"fixture-source",title:"Fixture",localPath:path,authorizationBasis:"Generated test media",profile:try profile(dir:dir),fileToDrive:false)
    }
}
