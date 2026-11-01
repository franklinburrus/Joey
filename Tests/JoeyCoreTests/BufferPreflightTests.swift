import XCTest
@testable import JoeyCore

final class BufferPreflightTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }
        return url
    }
    private func profile(_ directory: URL, owner: Owner = .dub) throws -> SharedProfile {
        var value = try Fixtures.profile(dir:directory)
        value.x!.account = owner == .dub ? "dubwiththefiles" : "JailCallwithTax"
        value.instagram!.account = owner == .dub ? "dubwiththefiles" : "thejailcallwithtaxstone"
        value.x!.surface = "Buffer X video"
        value.instagram!.surface = "Buffer Instagram Reel"
        value.x!.maxDuration = 140
        value.instagram!.maxBytes = 300_000_000
        value.x!.officialURLs = ["https://support.buffer.com/articles/sharing-videos-through-buffer-LOe2p2rnAI"]
        value.instagram!.officialURLs = value.x!.officialURLs
        return value
    }
    private func probe(duration: Double = 137) -> MediaProbe {
        MediaProbe(streams:[
            StreamInfo(codec_type:"video",codec_name:"h264",width:720,height:1280,pix_fmt:"yuv420p",field_order:"progressive",sample_aspect_ratio:"1:1",avg_frame_rate:"30/1",duration:String(duration),start_time:"0",bit_rate:"2000000"),
            StreamInfo(codec_type:"audio",codec_name:"aac",profile:"LC",duration:String(duration),start_time:"0",channels:2,sample_rate:"48000",bit_rate:"120000")
        ],format:MediaProbe.Format(duration:String(duration),size:"1000000",format_name:"mov,mp4,m4a,3gp,3g2,mj2"))
    }
    func testCapabilityCannotCrossOwnerOrUseExpiredOrNonBufferSurface() throws {
        let dir = try temporaryDirectory(), dub = try profile(dir), tax = try profile(dir,owner:.taxstone)
        XCTAssertNoThrow(try BufferPreflight.validateProfile(dub,owner:.dub,workflow:.link))
        XCTAssertNoThrow(try BufferPreflight.validateProfile(tax,owner:.taxstone,workflow:.taxstoneLibrary))
        XCTAssertThrowsError(try BufferPreflight.validateProfile(dub,owner:.taxstone,workflow:.taxstoneLibrary))
        XCTAssertThrowsError(try BufferPreflight.validateProfile(tax,owner:.dub,workflow:.link))
        XCTAssertThrowsError(try BufferPreflight.validateProfile(dub,owner:.dub,workflow:.joeBudden))
        var expired = dub; expired.x!.validUntil = Date().addingTimeInterval(-1)
        XCTAssertThrowsError(try BufferPreflight.validateProfile(expired,owner:.dub,workflow:.link))
        var wrongSurface = dub; wrongSurface.x!.surface = "X web upload"
        XCTAssertThrowsError(try BufferPreflight.validateProfile(wrongSurface,owner:.dub,workflow:.link))
    }
    func testTechnicalValidationUsesMeasuredLimitsAndEncodingMargin() throws {
        var caps = try profile(temporaryDirectory())
        XCTAssertNoThrow(try BufferPreflight.validateTechnical(probe(),bytes:1_000_000,expectedDuration:137,hasAudio:true,profile:caps))
        for length in [139.95,140,140.01,141] {
            XCTAssertThrowsError(try BufferPreflight.validateTechnical(probe(duration:length),bytes:1_000_000,expectedDuration:length,hasAudio:true,profile:caps))
        }
        caps.instagram!.maxDuration = 90
        XCTAssertThrowsError(try BufferPreflight.validateTechnical(probe(),bytes:1_000_000,expectedDuration:137,hasAudio:true,profile:caps))
        XCTAssertThrowsError(try BufferPreflight.validateTechnical(probe(duration:4),bytes:1_000_000,expectedDuration:4,hasAudio:true,profile:caps))
    }
    func testTechnicalValidationRejectsWrongCodecAudioRateInterlacingAndExtraStreams() throws {
        let caps = try profile(temporaryDirectory())
        var variants: [MediaProbe] = []
        var p = probe(); p.streams[0].codec_name = "hevc"; variants.append(p)
        p = probe(); p.streams[0].field_order = "tt"; variants.append(p)
        p = probe(); p.streams[0].sample_aspect_ratio = "4:3"; variants.append(p)
        p = probe(); p.streams[0].avg_frame_rate = "30000/1001"; variants.append(p)
        p = probe(); p.streams[0].bit_rate = "25000000"; variants.append(p)
        p = probe(); p.streams[1].bit_rate = "128000"; variants.append(p)
        p = probe(); p.streams[1].sample_rate = "44100"; variants.append(p)
        p = probe(); p.streams[1].profile = "HE-AAC"; variants.append(p)
        p = probe(); p.streams[1].start_time = "0.3"; variants.append(p)
        p = probe(); p.streams.append(StreamInfo(codec_type:"subtitle")); variants.append(p)
        p = probe(); p.format.format_name = "matroska"; variants.append(p)
        p = probe(); p.streams[0].width = 1080; variants.append(p)
        for invalid in variants {
            XCTAssertThrowsError(try BufferPreflight.validateTechnical(invalid,bytes:1_000_000,expectedDuration:137,hasAudio:true,profile:caps))
        }
        XCTAssertThrowsError(try BufferPreflight.validateTechnical(probe(),bytes:300_000_001,expectedDuration:137,hasAudio:true,profile:caps))
    }
    func testAnonymousURLRejectsCredentialsAndUnexpectedRedirectHosts() {
        for value in ["https://drive.google.com/uc?id=abc", "https://drive.usercontent.google.com/download?id=abc", "https://doc-01-14-docs.googleusercontent.com/docs/securesc/example"] {
            XCTAssertTrue(BufferPreflight.allowedMediaURL(URL(string:value)!))
        }
        for value in ["http://drive.google.com/x", "https://accounts.google.com/login", "https://drive.google.com.evil.test/x", "https://evil.googleusercontent.com/x", "https://secret@drive.google.com/x", "https://drive.google.com:8443/x", "file:///tmp/clip.mp4"] {
            XCTAssertFalse(BufferPreflight.allowedMediaURL(URL(string:value)!))
        }
    }
    func testRangeValidationRequiresExactMediaBytesAndTotalSize() throws {
        let bytes = Data([0,0,0,24,102,116,121,112]), url = URL(string:"https://drive.google.com/uc?id=abc")!
        let headers = ["Content-Type":"video/mp4","Content-Range":"bytes 0-7/1000000","Content-Length":"8"]
        let response = HTTPURLResponse(url:url,statusCode:206,httpVersion:nil,headerFields:headers)!
        XCTAssertNoThrow(try BufferPreflight.validateRange(response:response,data:bytes,expected:bytes,start:0,total:1_000_000))
        for altered in [bytes.dropLast(), Data(repeating:0,count:8)] {
            XCTAssertThrowsError(try BufferPreflight.validateRange(response:response,data:Data(altered),expected:bytes,start:0,total:1_000_000))
        }
        for badHeaders in [headers.merging(["Content-Type":"text/html"],uniquingKeysWith:{$1}),headers.merging(["Content-Range":"bytes 0-7/999999"],uniquingKeysWith:{$1})] {
            XCTAssertThrowsError(try BufferPreflight.validateRange(response:HTTPURLResponse(url:url,statusCode:206,httpVersion:nil,headerFields:badHeaders)!,data:bytes,expected:bytes,start:0,total:1_000_000))
        }
        XCTAssertThrowsError(try BufferPreflight.validateRange(response:HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:headers)!,data:bytes,expected:bytes,start:0,total:1_000_000))
    }

    private func completedJob(_ directory: URL) throws -> JobRecord {
        var request = try Fixtures.request(dir:directory,path:directory.appendingPathComponent("original.wav").path)
        request.fileToDrive = true
        var job = JobRecord(id:"test-completed-job",request:request)
        job.state = .completed; job.folderID = "episode-folder-id"
        let sha = String(repeating:"a",count:64)
        job.source = SourceRecord(id:request.sourceID,owner:.dub,title:"Test",path:request.localPath!,bytes:9000,sha256:sha,duration:137,width:720,height:1280,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic authorized fixture",classificationEvidence:"Synthetic")
        job.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:sha,duration:137,engine:"fixture",segments:[TranscriptSegment(start:0,end:137,text:"Complete source transcript")])
        let receipt = DriveReceipt(id:"accepted-output-id",name:"clip.mp4",parent:job.folderID!,bytes:1_000_000,md5:"accepted-md5",sha256:sha,url:"https://drive.google.com/file/d/accepted-output-id/view",permissions:["anyone:reader","user:owner"],verifiedAt:Date())
        job.clips = [ClipRecord(id:1,title:"Test clip",intervals:[Interval(0,137)],filename:"clip.mp4",measuredDuration:137,bytes:1_000_000,sha256:sha,qa:QAReport(checkedAt:Date(),checks:["audio_fidelity_sync":"Source PCM matched"],outputSHA256:sha,passed:true,limitations:[]),drive:receipt)]
        for name in ["clip_manifest.json","RECONCILE.md","Clip Index — Test.csv","Test — Full Transcript.txt"] {job.companions[name] = receipt}
        job.registerRows = ["Sheet!A2:ZZ2"]
        return job
    }

    func testCompletedEligibilityCannotBeInferredFromAcceptedLocalFile() throws {
        let job = try completedJob(temporaryDirectory()), clip = job.clips[0]
        XCTAssertNoThrow(try BufferPreflight.validateJob(job,clip:clip))
        var incomplete = job; incomplete.state = .qaPassed
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:clip))
        incomplete = job; incomplete.registerRows = []
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:clip))
        incomplete = job; incomplete.transcript!.sourceSHA256 = "other-source"
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:clip))
        incomplete = job; incomplete.source!.authorizationBasis = " "
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:clip))
        incomplete = job; incomplete.companions.removeValue(forKey:"RECONCILE.md")
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:clip))
        incomplete = job; incomplete.clips[0].qa!.checks.removeValue(forKey:"audio_fidelity_sync")
        XCTAssertThrowsError(try BufferPreflight.validateJob(incomplete,clip:incomplete.clips[0]))
        var alteredClip = clip; alteredClip.intervals = [Interval(0,100)]
        XCTAssertThrowsError(try BufferPreflight.validateJob(job,clip:alteredClip))
    }

    func testDriveReadbackRejectsWrongOwnerFolderHashDuplicatesAndAccessChanges() throws {
        let job = try completedJob(temporaryDirectory()), clip = job.clips[0], source = job.source!
        let file: [String:Any] = ["id":"accepted-output-id","name":"clip.mp4","mimeType":"video/mp4","trashed":false,"parents":["episode-folder-id"],"size":"1000000","md5Checksum":"accepted-md5","permissions":[["type":"anyone","role":"reader"],["type":"user","role":"owner"]]]
        let folder: [String:Any] = ["id":"episode-folder-id","mimeType":"application/vnd.google-apps.folder","trashed":false,"parents":[DriveDelivery.videoRoot],"appProperties":["joeySourceID":source.id,"joeyOwner":"dub"]]
        XCTAssertNoThrow(try BufferPreflight.validateDrive(file:file,folder:folder,source:source,clip:clip,folderID:"episode-folder-id",md5:"accepted-md5"))
        for change: [String:Any] in [["id":"other-output-id"],["md5Checksum":"different"],["parents":[DriveDelivery.audioRoot]],["trashed":true],["permissions":[["type":"anyone","role":"writer"]]]] {
            XCTAssertThrowsError(try BufferPreflight.validateDrive(file:file.merging(change,uniquingKeysWith:{$1}),folder:folder,source:source,clip:clip,folderID:"episode-folder-id",md5:"accepted-md5"))
        }
        var wrongOwner = folder; wrongOwner["appProperties"] = ["joeySourceID":source.id,"joeyOwner":"taxstone"]
        XCTAssertThrowsError(try BufferPreflight.validateDrive(file:file,folder:wrongOwner,source:source,clip:clip,folderID:"episode-folder-id",md5:"accepted-md5"))
    }

    func testAcceptedOutputPathRejectsTraversalAndSymbolicLinks() throws {
        let root = try temporaryDirectory(), job = root.appendingPathComponent("jobs/job")
        try FileManager.default.createDirectory(at:job,withIntermediateDirectories:true)
        let output = job.appendingPathComponent("clip.mp4")
        try Data("fixture".utf8).write(to:output)
        XCTAssertEqual(try BufferPreflight.acceptedFile(root:root,jobID:"job",filename:"clip.mp4"),output)
        for name in ["../clip.mp4","../../secret.mp4","/tmp/clip.mp4"] {
            XCTAssertThrowsError(try BufferPreflight.acceptedFile(root:root,jobID:"job",filename:name))
        }
        try FileManager.default.createSymbolicLink(at:job.appendingPathComponent("linked.mp4"),withDestinationURL:output)
        XCTAssertThrowsError(try BufferPreflight.acceptedFile(root:root,jobID:"job",filename:"linked.mp4"))
    }

    func testGeneratedMP4PassesCurrentProbeAndCompleteDecodeWhileTruncationFails() async throws {
        let root = try temporaryDirectory(), output = root.appendingPathComponent("generated.mp4"), caps = try profile(root)
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","color=c=purple:s=720x1280:r=30:d=6","-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=6","-c:v","libx264","-threads","1","-preset","ultrafast","-pix_fmt","yuv420p","-c:a","aac","-b:a","120k","-movflags","+faststart","-y",output.path])
        let (p,checks) = try await BufferPreflight.inspectMedia(output,expectedDuration:6,hasAudio:true,profile:caps)
        XCTAssertEqual(p.video?.width,720)
        XCTAssertEqual(p.audio?.codec_name,"aac")
        XCTAssertNotNil(checks["complete_decode"])
        let data = try Data(contentsOf:output)
        try data.prefix(data.count / 2).write(to:output)
        do {
            _ = try await BufferPreflight.inspectMedia(output,expectedDuration:6,hasAudio:true,profile:caps)
            XCTFail("Truncated media must not pass complete preflight")
        } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
    }

    func testAnonymousStreamingChecksBothRangesWithoutClaimingWholeFileHash() async throws {
        let directory = try temporaryDirectory(), local = directory.appendingPathComponent("accepted.mp4")
        let bytes = Data((0..<200_000).map {UInt8($0 % 251)})
        try bytes.write(to:local)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreflightMediaProtocol.self]
        PreflightMediaProtocol.body = bytes
        let result = try await BufferPreflight.verifyMediaURL(URL(string:"https://drive.google.com/valid")!,local:local,totalBytes:200_000,configuration:configuration)
        XCTAssertEqual(result.bytesVerified,131_072)
        XCTAssertEqual(result.ranges,["bytes=0-65535","bytes=134464-199999"])
        XCTAssertNil(result.fullFileSHA256)
        XCTAssertEqual(result.totalBytes,200_000)
        XCTAssertEqual(result.rangeSHA256.count,2)
        XCTAssertGreaterThan(result.validUntil,result.checkedAt)
    }

    func testAnonymousStreamingRejectsHTMLUnboundedOrChangedResponses() async throws {
        let directory = try temporaryDirectory(), local = directory.appendingPathComponent("accepted.mp4")
        let bytes = Data(repeating:23,count:200_000)
        try bytes.write(to:local)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreflightMediaProtocol.self]
        PreflightMediaProtocol.body = bytes
        for path in ["html","oversize","changed","full","auth"] {
            do {
                _ = try await BufferPreflight.verifyMediaURL(URL(string:"https://drive.google.com/"+path)!,local:local,totalBytes:200_000,configuration:configuration)
                XCTFail("Anonymous media must reject \(path)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }
}

private final class PreflightMediaProtocol: URLProtocol {
    // These fixture tests execute serially; no real network or credentials.
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool {request.url?.host == "drive.google.com"}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        guard request.value(forHTTPHeaderField:"Authorization") == nil,
              request.value(forHTTPHeaderField:"Cookie") == nil,
              let raw = request.value(forHTTPHeaderField:"Range"), raw.hasPrefix("bytes=") else {
            client?.urlProtocol(self,didFailWithError:JoeyError.failed("Anonymous request leaked authentication or lacked a range")); return
        }
        let bounds = raw.dropFirst(6).split(separator:"-").compactMap {Int($0)}
        guard bounds.count == 2 else {client?.urlProtocol(self,didFailWithError:JoeyError.failed("Invalid range")); return}
        let path = request.url!.lastPathComponent
        var part = Self.body.subdata(in:bounds[0]..<bounds[1]+1)
        if path == "oversize" {part.append(1)}
        if path == "changed" {part[0] = 1}
        let code = path == "auth" ? 401 : (path == "full" ? 200 : 206)
        let headers = ["Content-Type":path == "html" ? "text/html" : "video/mp4",
            "Content-Range":"bytes \(bounds[0])-\(bounds[1])/\(Self.body.count)"]
        let response = HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:part)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
