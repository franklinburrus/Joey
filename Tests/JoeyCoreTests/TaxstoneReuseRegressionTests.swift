import XCTest
@testable import JoeyCore

final class TaxstoneReuseRegressionTests: XCTestCase {
    private let fm = FileManager.default
    private let validID = "synthetic_legacy_object_001"

    private func fixture() throws -> (URL, URL, JobRequest, SourceRecord, Transcript) {
        let base = try StorageManager.canonicalRoot(fm.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        let job = base.appendingPathComponent("job")
        try fm.createDirectory(at:job,withIntermediateDirectories:true)
        var request = try Fixtures.request(dir:base,path:"unused")
        request.owner = .taxstone
        let artwork = base.appendingPathComponent("artwork.fixture")
        try Data("Synthetic artwork identity for cached QA".utf8).write(to:artwork)
        request.artwork = Artwork(owner:.taxstone,sourceID:request.sourceID,driveID:"synthetic_artwork",
            file:EvidenceFile(path:artwork.path,sha256:try Integrity.sha256(artwork),basis:"Synthetic reuse fixture only"))
        let source = SourceRecord(id:request.sourceID,owner:.taxstone,title:"Synthetic episode",path:"unused",bytes:1,
            sha256:"synthetic-source",duration:12,width:0,height:0,fps:0,hasAudio:true,kind:.audio,streams:[],
            authorizationBasis:"Synthetic reuse fixture only",classificationEvidence:"Synthetic audio")
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:12,engine:"synthetic",
            segments:(0..<12).map {TranscriptSegment(start:Double($0),end:Double($0+1),text:"Sentence \($0).")})
        return (base,job,request,source,transcript)
    }

    private func cache(_ qa: QAReport, driveID: String, intervals: [Interval], request: JobRequest,
                       source: SourceRecord, transcript: Transcript, job: URL) throws {
        let title = transcript.segments.first {segment in
            intervals.contains {segment.start >= $0.start && segment.end <= $0.end}
        }?.text ?? source.title
        let clip = ClipRecord(id:0,title:String(title.split(separator:" ").prefix(12).joined(separator:" ")),
            intervals:intervals,filename:"candidate.mp4")
        let accepted = TaxstoneReuseAcceptance(source:source,clip:clip,profile:request.profile,
            artwork:try XCTUnwrap(request.artwork),qa:qa)
        try Persistence.save(accepted,to:job.appendingPathComponent("legacy-reuse/\(driveID)/accepted-qa-bound.json"))
    }

    func testUnsafeImportedIDsNeverCreatePathsOrCallProvider() async throws {
        for id in ["../../escaped","../../escaped_long_legacy_object","nested/object","synthetic_legacy_object/escape",
                   "nested\\object","synthetic_legacy_object\\escape","/absolute/object","/absolute_synthetic_legacy_object",
                   "..",".","","encoded%2Fobject","synthetic_legacy_object\0escape"] {
            let (base,job,initial,source,transcript) = try fixture()
            defer {try? fm.removeItem(at:base)}
            var request = initial
            request.taxstoneReuse = [TaxstoneReuseInput(driveID:id,intervals:[Interval(0,13)],
                sourceSHA256:source.sha256,md5:"synthetic",evidence:"Synthetic invalid interval")]
            let provider = ReuseFixtureProvider()
            do {
                _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                    exclusions:[],provider:provider,directory:job)
                XCTFail("Unsafe imported ID was accepted: \(id)")
            } catch {
                XCTAssertTrue(error is JoeyError)
            }
            XCTAssertFalse(fm.fileExists(atPath:job.appendingPathComponent("legacy-reuse").path),id)
            XCTAssertFalse(fm.fileExists(atPath:base.appendingPathComponent("escaped").path),id)
            XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath:base.path)),["job","capability-evidence.txt","artwork.fixture"],id)
            let calls = await provider.calls
            XCTAssertEqual(calls,[],id)
        }
    }

    func testSymlinkedReuseDirectoriesAndReceiptsNeverWriteOutsideOrCallProvider() async throws {
        for relative in ["legacy-reuse", "legacy-reuse/\(validID)", "legacy-reuse/\(validID)/reconciliation.json",
                         "legacy-reuse/\(validID)/original-download.partial", "evidence"] {
            let (base,job,initial,source,transcript) = try fixture()
            defer {try? fm.removeItem(at:base)}
            let outside = base.appendingPathComponent("outside")
            try fm.createDirectory(at:outside,withIntermediateDirectories:true)
            let sentinel = outside.appendingPathComponent("sentinel")
            let bytes = Data("preserve outside bytes".utf8)
            try bytes.write(to:sentinel)
            let link = job.appendingPathComponent(relative)
            try fm.createDirectory(at:link.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.createSymbolicLink(at:link,withDestinationURL:relative.contains(".") ? sentinel : outside)
            var request = initial
            request.taxstoneReuse = [TaxstoneReuseInput(driveID:validID,intervals:[Interval(0,13)],
                sourceSHA256:source.sha256,md5:"synthetic",evidence:"Synthetic invalid interval")]
            let provider = ReuseFixtureProvider()
            do {
                _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                    exclusions:[],provider:provider,directory:job)
                XCTFail("Linked reuse path was accepted: \(relative)")
            } catch {XCTAssertTrue(error is JoeyError)}
            XCTAssertEqual(try Data(contentsOf:sentinel),bytes,relative)
            XCTAssertEqual(try fm.contentsOfDirectory(atPath:outside.path),["sentinel"],relative)
            XCTAssertNoThrow(try fm.destinationOfSymbolicLink(atPath:link.path),relative)
            let calls = await provider.calls
            XCTAssertEqual(calls,[],relative)
        }
    }

    func testImportedIDMustMatchEntireIdentityBeforeAnyProviderCall() async throws {
        for ids in [[validID+"\n"], [validID,"../../escaped"]] {
            let (base,job,initial,source,transcript) = try fixture()
            defer {try? fm.removeItem(at:base)}
            var request = initial
            request.taxstoneReuse = ids.enumerated().map { index, id in
                TaxstoneReuseInput(driveID:id,intervals:[Interval(Double(index),Double(index+1))],
                    sourceSHA256:source.sha256,md5:"synthetic",evidence:"Synthetic identity validation")
            }
            let provider = ReuseFixtureProvider()
            do {
                _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                    exclusions:[],provider:provider,directory:job)
                XCTFail("Invalid inventory was accepted")
            } catch {XCTAssertTrue(error is JoeyError)}
            XCTAssertFalse(fm.fileExists(atPath:job.appendingPathComponent("legacy-reuse").path))
            let calls = await provider.calls
            XCTAssertEqual(calls,[])
        }
    }

    func testLinkedJobAncestorCannotRedefineAuthorizedWorkspace() async throws {
        let (base,_,initial,source,transcript) = try fixture()
        defer {try? fm.removeItem(at:base)}
        let outside = base.appendingPathComponent("outside")
        let actualJob = outside.appendingPathComponent("job")
        try fm.createDirectory(at:actualJob,withIntermediateDirectories:true)
        let sentinel = actualJob.appendingPathComponent("sentinel")
        let bytes = Data("outside identity must remain unchanged".utf8)
        try bytes.write(to:sentinel)
        let link = base.appendingPathComponent("jobs")
        try fm.createSymbolicLink(at:link,withDestinationURL:outside)
        var request = initial
        request.taxstoneReuse = [TaxstoneReuseInput(driveID:validID,intervals:[Interval(0,13)],
            sourceSHA256:source.sha256,md5:"synthetic",evidence:"Synthetic invalid interval")]
        let provider = ReuseFixtureProvider()
        do {
            _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                exclusions:[],provider:provider,directory:link.appendingPathComponent("job"))
            XCTFail("A symlink ancestor redefined the authorized workspace")
        } catch {XCTAssertTrue(error is JoeyError)}
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:actualJob.path),["sentinel"])
        XCTAssertEqual(try Data(contentsOf:sentinel),bytes)
        let calls = await provider.calls
        XCTAssertEqual(calls,[])
    }

    func testMissingRegionsStayChronologicalAndPreserveAcceptedIdentities() async throws {
        // Literal expectations expose the old compaction of gaps across an
        // accepted clip. Every synthetic source second must occur exactly once.
        let cases: [([[Interval]], [Interval], [[Interval]])] = [
            ([[Interval(0,1)]],[],[[Interval(0,1)],[Interval(1,12)]]),
            ([[Interval(5,6)]],[],[[Interval(0,5)],[Interval(5,6)],[Interval(6,12)]]),
            ([[Interval(11,12)]],[],[[Interval(0,11)],[Interval(11,12)]]),
            ([[Interval(3,4)],[Interval(8,9)]],[],[[Interval(0,3)],[Interval(3,4)],[Interval(4,8)],[Interval(8,9)],[Interval(9,12)]]),
            ([[Interval(3,4)],[Interval(8,9)]],[Interval(1,2),Interval(6,7),Interval(10,11)],
             [[Interval(0,1),Interval(2,3)],[Interval(3,4)],[Interval(4,6),Interval(7,8)],[Interval(8,9)],[Interval(9,10),Interval(11,12)]])
        ]
        let (mediaBase,_,_,_,_) = try fixture()
        defer {try? fm.removeItem(at:mediaBase)}
        let media = mediaBase.appendingPathComponent("accepted.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","color=c=black:s=720x1280:r=30:d=1",
            "-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-t","1","-c:v","libx264","-preset","ultrafast",
            "-pix_fmt","yuv420p","-c:a","aac","-movflags","+faststart",media.path])
        let acceptedBytes = try Data(contentsOf:media)
        let hash = try Integrity.sha256(media), md5 = try Integrity.md5(media)
        for (accepted,ads,expected) in cases {
            let (base,job,initial,source,transcript) = try fixture()
            defer {try? fm.removeItem(at:base)}
            var request = initial
            request.taxstoneReuse = try accepted.enumerated().map { index, intervals in
                let id = "synthetic_legacy_object_\(index)"
                let qa = QAReport(checkedAt:Date(timeIntervalSince1970:1_000),checks:["provider_identity":id],
                    outputSHA256:hash,passed:true,limitations:["Synthetic cached acceptance for reuse planning only"])
                try cache(qa,driveID:id,intervals:intervals,request:request,source:source,transcript:transcript,job:job)
                return TaxstoneReuseInput(driveID:id,intervals:intervals,sourceSHA256:source.sha256,
                    md5:md5,evidence:"Synthetic accepted object")
            }
            let provider = ReuseFixtureProvider(media:media,md5:md5)
            let exclusions = ads.map {AdExclusion(interval:$0,evidence:"Synthetic explicit ad",confidence:1)}
            do {
                let clips = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                    exclusions:exclusions,provider:provider,directory:job)
                XCTAssertEqual(clips.map(\.intervals),expected)
                XCTAssertEqual(clips.map(\.id),Array(1...expected.count))
                for (index,intervals) in accepted.enumerated() {
                    let clip = try XCTUnwrap(clips.first {$0.intervals == intervals})
                    XCTAssertEqual(clip.sha256,hash)
                    XCTAssertEqual(clip.qa?.checks["provider_identity"],"synthetic_legacy_object_\(index)")
                    XCTAssertEqual(try Data(contentsOf:job.appendingPathComponent(clip.filename)),acceptedBytes)
                    XCTAssertEqual(try Data(contentsOf:job.appendingPathComponent("legacy-reuse/synthetic_legacy_object_\(index)/original.mp4")),acceptedBytes)
                    let saved: QAReport = try Persistence.load(job.appendingPathComponent("evidence/\(clip.id)/qa.json"))
                    XCTAssertEqual(saved,clip.qa)
                }
                for second in 0..<12 {
                    let time = Double(second)+0.5
                    let occurrences = clips.flatMap(\.intervals).filter {$0.start <= time && time < $0.end}.count
                    XCTAssertEqual(occurrences,ads.contains {$0.start <= time && time < $0.end} ? 0 : 1)
                }
                if accepted.count > 1 {
                    let acceptedFiles = clips.filter {$0.qa != nil}.map {job.appendingPathComponent($0.filename)}
                    let identities = try acceptedFiles.map {try fm.attributesOfItem(atPath:$0.path)}
                    let resumed = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                        exclusions:exclusions,provider:provider,directory:job)
                    XCTAssertEqual(resumed,clips)
                    for (file,identity) in zip(acceptedFiles,identities) {
                        let fresh = try fm.attributesOfItem(atPath:file.path)
                        XCTAssertEqual(fresh[.systemFileNumber] as? NSNumber,identity[.systemFileNumber] as? NSNumber)
                        XCTAssertEqual(fresh[.modificationDate] as? Date,identity[.modificationDate] as? Date)
                    }
                }
            } catch {
                XCTFail("Missing-region planning failed for \(accepted), ads \(ads): \(error)")
            }
        }
    }

    func testSameProviderObjectCannotReuseQAForDifferentSourceIntervals() async throws {
        let (base,job,initial,_,_) = try fixture()
        defer {try? fm.removeItem(at:base)}
        let original = base.appendingPathComponent("source.wav")
        let artworkURL = base.appendingPathComponent("artwork.png")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i",
            "aevalsrc=0.25*sin(2*PI*(440+220*floor(t))*t):s=48000:d=3",original.path])
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=300x300",
            "-frames:v","1",artworkURL.path])
        var request = initial
        request.artwork = Artwork(owner:.taxstone,sourceID:request.sourceID,driveID:"synthetic_artwork",
            file:EvidenceFile(path:artworkURL.path,sha256:try Integrity.sha256(artworkURL),basis:"Synthetic episode artwork"))
        let source = try await Media.inspect(original,request:request)
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:source.duration,engine:"synthetic",
            segments:(0..<3).map {TranscriptSegment(start:Double($0),end:Double($0+1),text:"Sentence \($0).")})
        let clip = ClipRecord(id:1,title:"Sentence 0.",intervals:[Interval(0,1)],filename:"accepted.mp4")
        let media = base.appendingPathComponent(clip.filename)
        _ = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:request.artwork,
            work:base,output:media)
        let hash = try Integrity.sha256(media),md5 = try Integrity.md5(media)
        let historicalURL = job.appendingPathComponent("legacy-reuse/\(validID)/accepted-qa.json")
        try Persistence.save(QAReport(checkedAt:Date(timeIntervalSince1970:1_000),checks:["unbound":"historical"],
            outputSHA256:hash,passed:true,limitations:["Unbound synthetic historical QA"]),to:historicalURL)
        let historicalBytes = try Data(contentsOf:historicalURL)
        request.taxstoneReuse = [Interval(0,1),Interval(2,3)].map {
            TaxstoneReuseInput(driveID:validID,intervals:[$0],sourceSHA256:source.sha256,md5:md5,
                evidence:"Conflicting historical mappings for the same provider object")
        }
        do {
            _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,exclusions:[],
                provider:ReuseFixtureProvider(media:media,md5:md5),directory:job)
            XCTFail("Identical legacy media was accepted for two different source intervals")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Audio fidelity/sync failed"),error.localizedDescription)
        }
        XCTAssertEqual(try Integrity.sha256(media),hash)
        XCTAssertEqual(try Integrity.sha256(job.appendingPathComponent("legacy-reuse/\(validID)/original.mp4")),hash)
        XCTAssertEqual(try Data(contentsOf:historicalURL),historicalBytes,"Unbound historical evidence must be preserved")
        let accepted: TaxstoneReuseAcceptance = try Persistence.load(job.appendingPathComponent("legacy-reuse/\(validID)/accepted-qa-bound.json"))
        XCTAssertNil(accepted.qa.checks["unbound"],"Historical QA must be independently revalidated before reuse")
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:job.path).contains {$0.hasSuffix(".mp4")})
    }

    func testBufferReuseCompactsAdsWithinGapsAndRejectsCachedOutOfPolicyDuration() async throws {
        let cases: [(Double,Double,Interval,[Interval],Bool)] = [
            (6,30,Interval(12,18),[Interval(1,5)],true),
            (1,12,Interval(5,6),[],false),
            (140,300,Interval(0,140),[],false)
        ]
        for (duration,total,interval,ads,adopted) in cases {
            let (base,job,initial,original,_) = try fixture()
            defer {try? fm.removeItem(at:base)}
            let media = base.appendingPathComponent("accepted.mp4")
            _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","color=c=black:s=720x1280:r=30:d=\(duration)",
                "-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-t",String(duration),"-c:v","libx264","-preset","ultrafast",
                "-pix_fmt","yuv420p","-c:a","aac","-movflags","+faststart",media.path])
            let originalBytes = try Data(contentsOf:media)
            let hash = try Integrity.sha256(media), md5 = try Integrity.md5(media)
            var request = initial; request.profile.x?.surface = "Buffer synthetic test surface"
            var source = original; source.duration = total
            let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:total,engine:"synthetic",
                segments:[TranscriptSegment(start:0,end:total,text:"Synthetic full episode.")])
            let qa = QAReport(checkedAt:Date(timeIntervalSince1970:1_000),checks:["provider_identity":validID],
                outputSHA256:hash,passed:true,limitations:["Synthetic cached acceptance only"])
            try cache(qa,driveID:validID,intervals:[interval],request:request,source:source,transcript:transcript,job:job)
            request.taxstoneReuse = [TaxstoneReuseInput(driveID:validID,intervals:[interval],sourceSHA256:source.sha256,
                md5:md5,evidence:"Synthetic cached acceptance")]
            let provider = ReuseFixtureProvider(media:media,md5:md5)
            do {
                let clips = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,
                    exclusions:ads.map {AdExclusion(interval:$0,evidence:"Synthetic explicit ad",confidence:1)},
                    provider:provider,directory:job)
                if adopted {
                    XCTAssertEqual(clips.map(\.intervals),[[Interval(0,1),Interval(5,12)],[Interval(12,18)],[Interval(18,30)]])
                    XCTAssertEqual(clips[1].sha256,hash)
                    XCTAssertEqual(try Data(contentsOf:job.appendingPathComponent(clips[1].filename)),originalBytes)
                } else {
                    XCTAssertTrue(clips.allSatisfy {$0.qa == nil && $0.sha256 == nil},"Cached acceptance bypassed current duration policy")
                    let reconciliation: [String:String] = try Persistence.load(job.appendingPathComponent("legacy-reuse/\(validID)/reconciliation.json"))
                    XCTAssertEqual(reconciliation["status"],"INCOMPATIBLE")
                }
                XCTAssertTrue(clips.allSatisfy {$0.expectedDuration >= 5 && $0.expectedDuration <= 139.825+0.000001},
                    "Unexpected planned durations: \(clips.map(\.expectedDuration))")
                XCTAssertNoThrow(try Planning.validateCoverage(duration:total,exclusions:ads,clips:clips.map(\.intervals)))
                XCTAssertEqual(try Data(contentsOf:job.appendingPathComponent("legacy-reuse/\(validID)/original.mp4")),originalBytes)
            } catch {XCTFail("Buffer reuse scenario \(duration)s failed: \(error)")}
        }
    }

    func testImpossibleBufferGapFailsWithoutReplacingAcceptedMedia() async throws {
        let (base,job,initial,source,transcript) = try fixture()
        defer {try? fm.removeItem(at:base)}
        let media = base.appendingPathComponent("accepted.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","color=c=black:s=720x1280:r=30:d=6",
            "-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-t","6","-c:v","libx264","-preset","ultrafast",
            "-pix_fmt","yuv420p","-c:a","aac","-movflags","+faststart",media.path])
        let bytes = try Data(contentsOf:media), hash = try Integrity.sha256(media), md5 = try Integrity.md5(media)
        var request = initial; request.profile.x?.surface = "Buffer synthetic test surface"
        request.taxstoneReuse = [TaxstoneReuseInput(driveID:validID,intervals:[Interval(1,7)],sourceSHA256:source.sha256,
            md5:md5,evidence:"Synthetic accepted six-second clip")]
        try cache(QAReport(checkedAt:Date(timeIntervalSince1970:1_000),checks:[:],outputSHA256:hash,
            passed:true,limitations:["Synthetic cached acceptance only"]),driveID:validID,intervals:[Interval(1,7)],
            request:request,source:source,transcript:transcript,job:job)
        do {
            _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,exclusions:[],
                provider:ReuseFixtureProvider(media:media,md5:md5),directory:job)
            XCTFail("A one-second missing prefix cannot satisfy Buffer's minimum while retaining the accepted clip")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("shared minimum duration"),"\(error)")
        }
        XCTAssertEqual(try Data(contentsOf:job.appendingPathComponent("legacy-reuse/\(validID)/original.mp4")),bytes)
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:job.path).contains {$0.hasSuffix(".mp4")})
    }
}

private actor ReuseFixtureProvider: TaxstoneReuseProvider {
    private let media: URL?
    private let md5: String
    private(set) var calls: [String] = []
    init(media: URL? = nil, md5: String = "synthetic") {self.media = media;self.md5 = md5}
    func metadata(_ id: String) async throws -> [String: Any] {
        calls.append("metadata:\(id)")
        guard media != nil else {throw JoeyError.dependency("Synthetic provider must not be called")}
        return ["id":id,"name":"accepted.mp4","md5Checksum":md5]
    }
    func downloadOriginal(reference: String, directory: URL) async throws -> URL {
        calls.append("download:\(reference)")
        guard let media else {throw JoeyError.dependency("Synthetic provider must not be called")}
        let destination = directory.appendingPathComponent("original.mp4")
        if !FileManager.default.fileExists(atPath:destination.path) {
            try FileManager.default.copyItem(at:media,to:destination)
        }
        return destination
    }
}
