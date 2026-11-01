import XCTest
@testable import JoeyCore

final class BufferHandoffTests: XCTestCase {
    func testDurableSubBatchesReservationsAndMissingReceipts() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root)
        let clips = try (1...3).map {try prepared(root:root,id:$0)}
        for clip in clips {try store.savePreparation(clip)}
        var selection = BufferSelection();selection.clipKeys = clips.map(\.key);selection.platforms = [.x,.instagram]
        selection.instagramPresentation = .reelSharedToFeed;selection.instagramAcknowledged = true
        let currentChannels = channels()
        let first = try store.generate(selection:selection,channels:currentChannels)
        XCTAssertEqual(first.expectedOperationCount,6)
        XCTAssertEqual(first.subBatches.map { $0.operationIDs.count },[5,1])
        XCTAssertTrue(first.operations.allSatisfy {$0.state == .prepared})
        let restart = try BufferHandoffStore(root:root)
        let repeated = try restart.generate(selection:selection,channels:currentChannels)
        XCTAssertEqual(first.id,repeated.id,"Exporting twice must reuse the reservation")
        XCTAssertEqual(try restart.snapshot().batches.count,1)
        XCTAssertEqual(try restart.unresolved(first.id),6,"No receipt is not success")
        selection.clipKeys = [clips[0].key]
        let overlap = try restart.generate(selection:selection,channels:channels())
        XCTAssertTrue(overlap.operations.allSatisfy {$0.state == .blocked && !$0.priorBatchIDs.isEmpty})
        let folder = try restart.export(first)
        let readback: BufferManifest = try Persistence.load(folder.appendingPathComponent("manifest.json"))
        try readback.validate()
        XCTAssertEqual(try Integrity.sha256(folder.appendingPathComponent("manifest-canonical.json")),first.manifestSHA256)
    }

    func testReceiptImportPreservesPartialSuccessRejectsConflictsAndSurvivesRestart() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root), clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key];selection.platforms = [.x,.instagram]
        selection.instagramPresentation = .reel;selection.instagramAcknowledged = true
        let batch = try store.generate(selection:selection,channels:channels())
        let good = receipt(batch,operation:batch.operations[0])
        var package = BufferReceiptPackage(batchID:batch.id,manifestSHA256:batch.manifestSHA256,results:[good])
        try store.importReceipts(package)
        try store.importReceipts(package)
        XCTAssertEqual(try store.snapshot().receipts.count,1)
        XCTAssertEqual(try store.unresolved(batch.id),1)
        var bad = good;bad.channelID = "wrong"
        package.results = [bad];XCTAssertThrowsError(try store.importReceipts(package))
        bad = good;bad.clipID = 99;package.results = [bad];XCTAssertThrowsError(try store.importReceipts(package))
        bad = good;bad.batchID = UUID().uuidString;package.results = [bad];XCTAssertThrowsError(try store.importReceipts(package))
        bad = good;bad.postID = "different";package.results = [bad];XCTAssertThrowsError(try store.importReceipts(package))
        bad = good;bad.providerState = .sent;package.results = [bad];XCTAssertThrowsError(try store.importReceipts(package),"Draft authority must never be promoted to published")
        bad = good;bad.provenance = "Independently verified by Joey";package.results = [bad]
        XCTAssertThrowsError(try store.importReceipts(package))
        var uncertain = receipt(batch,operation:batch.operations[1]);uncertain.postID = nil;uncertain.providerState = nil
        uncertain.reconciliationState = .unconfirmed;uncertain.readbackAt = nil;uncertain.errors = ["Timeout after possible acceptance"]
        package.results = [uncertain];try store.importReceipts(package)
        XCTAssertEqual(try BufferHandoffStore(root:root).snapshot().receipts.count,2)
        XCTAssertEqual(try store.unresolved(batch.id),1)
        var downgrade = good;downgrade.reconciliationState = .unconfirmed;downgrade.readbackAt = nil
        package.results = [downgrade];XCTAssertThrowsError(try store.importReceipts(package))
    }

    func testFailedPreflightInvalidatesAnUnexpiredPreparedManifest() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root)
        var clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        let original = try store.generate(selection:selection,channels:channels())
        let originalExport = try store.export(original)
        clip.error = "Current Drive output is no longer accessible"
        clip.media = nil
        try store.savePreparation(clip)

        let refreshed = try store.generate(selection:selection,channels:channels())

        XCTAssertEqual(refreshed.id,original.id)
        XCTAssertEqual(refreshed.operations[0].id,original.operations[0].id)
        XCTAssertEqual(refreshed.operations[0].state,.blocked)
        XCTAssertTrue(refreshed.operations[0].blockers.contains(clip.error!))
        XCTAssertNotEqual(refreshed.manifestSHA256,original.manifestSHA256)
        let preserved: BufferManifest = try Persistence.load(originalExport.appendingPathComponent("manifest.json"))
        XCTAssertEqual(preserved.manifestSHA256,original.manifestSHA256)
    }

    func testChangedChannelEvidenceInvalidatesAnUnexpiredPreparedManifest() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        var currentChannels = channels()
        let original = try store.generate(selection:selection,channels:currentChannels)
        currentChannels[0].locked = true

        let refreshed = try store.generate(selection:selection,channels:currentChannels)

        XCTAssertEqual(refreshed.id,original.id)
        XCTAssertEqual(refreshed.operations[0].id,original.operations[0].id)
        XCTAssertEqual(refreshed.operations[0].state,.blocked)
        XCTAssertEqual(refreshed.operations[0].channel?.locked,true)
    }

    func testInvalidChannelExpiredEvidenceAndCompetingLockBlock() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root), clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        var badChannels = channels();badChannels[0].handle = "dubwiththefiles"
        let blocked = try store.generate(selection:selection,channels:badChannels)
        XCTAssertEqual(blocked.operations[0].state,.blocked)
        let lock = try ProcessingLock(directory:root.appendingPathComponent("buffer"),name:"handoff.lock")
        try withExtendedLifetime(lock) {XCTAssertThrowsError(try store.saveSelection(selection))}
        var json = try Persistence.encoder.encode(blocked)
        let text = String(decoding:json,as:UTF8.self).replacingOccurrences(of:"BLOCKED",with:"INVENTED")
        json = Data(text.utf8)
        XCTAssertThrowsError(try Persistence.decoder.decode(BufferManifest.self,from:json))
    }

    func testRehashedManifestCannotChangeOperationIdentityOrSelection() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        let batch = try store.generate(selection:selection,channels:channels())
        var altered = batch;altered.operations[0].clip.intervals = [Interval(0,9)]
        altered.manifestSHA256 = try altered.digest()
        XCTAssertThrowsError(try altered.validate())
        altered = batch;altered.selection.platforms = [.instagram];altered.manifestSHA256 = try altered.digest()
        XCTAssertThrowsError(try altered.validate())
    }

    func testExpiredHandoffRenewsEvidenceUnderSameParentAndKeepsOldExport() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        let first = try store.generate(selection:selection,channels:channels())
        let oldExport = try store.export(first)
        var renewed = clip;renewed.media?.checkedAt = Date().addingTimeInterval(400)
        renewed.media?.validUntil = Date().addingTimeInterval(600)
        renewed.media?.urlEvidence.validUntil = Date().addingTimeInterval(600)
        try store.savePreparation(renewed)
        let next = try store.generate(selection:selection,channels:channels(),now:Date().addingTimeInterval(401))
        XCTAssertEqual(next.id,first.id)
        XCTAssertNotEqual(next.manifestSHA256,first.manifestSHA256)
        XCTAssertEqual(next.operations[0].id,first.operations[0].id)
        XCTAssertEqual(next.operations[0].state,.prepared)
        XCTAssertNotEqual(try store.export(next),oldExport)
        let old: BufferManifest = try Persistence.load(oldExport.appendingPathComponent("manifest.json"))
        XCTAssertEqual(old.manifestSHA256,first.manifestSHA256)
    }

    func testExistingPostReconciliationDoesNotResolveDifferentModeBatch() throws {
        let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
        try store.savePreparation(clip)
        var selection = BufferSelection();selection.clipKeys = [clip.key]
        let draft = try store.generate(selection:selection,channels:channels())
        var known = receipt(draft,operation:draft.operations[0]);known.submissionOrigin = .existingPost
        known.submittedAt = Date().addingTimeInterval(-86400)
        try store.importReceipts(BufferReceiptPackage(batchID:draft.id,manifestSHA256:draft.manifestSHA256,results:[known]))
        selection.mode = .queue
        let queue = try store.generate(selection:selection,channels:channels())
        XCTAssertEqual(try store.unresolved(queue.id),1,"An earlier draft cannot complete a queue request")
        XCTAssertEqual(queue.operations[0].state,.blocked)
        XCTAssertEqual(queue.priorReceipts.first?.postID,known.postID)
    }

    func testCurrentManifestExistingDraftReceiptCannotResolveQueueOrSchedule() throws {
        for mode in [BufferMode.queue,.scheduled] {
            let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
            let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
            try store.savePreparation(clip)
            var selection = BufferSelection();selection.clipKeys = [clip.key];selection.mode = mode
            if mode == .scheduled {selection.scheduledAt = Date().addingTimeInterval(3600)}
            let batch = try store.generate(selection:selection,channels:channels())
            var known = receipt(batch,operation:batch.operations[0])
            known.requestedMode = mode
            known.submissionOrigin = .existingPost
            known.submittedAt = Date().addingTimeInterval(-86400)
            try store.importReceipts(BufferReceiptPackage(batchID:batch.id,manifestSHA256:batch.manifestSHA256,results:[known]))

            XCTAssertEqual(try store.unresolved(batch.id),1,"An existing draft does not fulfill a \(mode.rawValue) request")
            XCTAssertEqual(try store.snapshot().receipts.last?.postID,known.postID,"Keep existing provider identity for reconciliation")
        }
    }

    func testExistingScheduledSentSendingAndErrorRecordsPreventRecreation() throws {
        for status in [BufferProviderState.scheduled,.sending,.sent,.error] {
            let root = try temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
            let store = try BufferHandoffStore(root:root),clip = try prepared(root:root,id:1)
            try store.savePreparation(clip)
            var selection = BufferSelection();selection.clipKeys = [clip.key]
            let original = try store.generate(selection:selection,channels:channels())
            var known = receipt(original,operation:original.operations[0]);known.submissionOrigin = .existingPost;known.providerState = status
            try store.importReceipts(BufferReceiptPackage(batchID:original.id,manifestSHA256:original.manifestSHA256,results:[known]))
            let resumed = try store.generate(selection:selection,channels:channels())
            XCTAssertEqual(resumed.id,original.id)
            XCTAssertEqual(resumed.operations[0].state,.blocked)
            XCTAssertEqual(resumed.priorReceipts.first?.providerState,status)
            XCTAssertEqual(try store.unresolved(resumed.id),1)
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joey-handoff-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return root
    }
    private func channels() -> [BufferChannel] {
        let now = Date().addingTimeInterval(-2)
        return [.x,.instagram].map {platform in
            BufferChannel(lane:"taxstone",platform:platform,organizationID:"tax-org",channelID:platform == .x ? "tax-x":"tax-ig",handle:platform == .x ? "JailCallwithTax":"thejailcallwithtaxstone",connected:true,locked:false,checkedAt:now,validUntil:now.addingTimeInterval(3600),supportedModes:[.draft,.queue,.scheduled],supportedInstagramPresentations:[.reel,.reelSharedToFeed],evidenceSource:"Isolated fixture, no provider call",remainingAllowances:[100,500,1000])
        }
    }
    private func prepared(root: URL,id: Int) throws -> BufferPreparedClip {
        let now = Date().addingTimeInterval(-2), sha = String(repeating:"a",count:64)
        let recommendation = ClipRecommendation(title:"Music production",topic:"Music",xCaption:"Music production discussion.",instagramCaption:"Music production discussion.",xScore:50,instagramScore:55,rationale:["Fixture evidence"],confidence:"Low",boundaryNotes:[],restrictions:[],transcriptEvidence:[])
        let url = MediaURLVerification(checkedAt:now,validUntil:now.addingTimeInterval(300),method:"Isolated fixture",contentType:"video/mp4",bytesVerified:100,fullFileSHA256:nil,totalBytes:1000,ranges:["0-99"],rangeSHA256:[sha],finalURLs:["https://drive.google.com/uc?export=download&id=fixture"])
        var profile = try Fixtures.profile(dir:root)
        profile.x?.account = "JailCallwithTax";profile.instagram?.account = "thejailcallwithtaxstone"
        let media = BufferMediaPreflight(checkedAt:now,validUntil:now.addingTimeInterval(300),sha256:sha,bytes:1000,duration:10,width:720,height:1280,fps:30,videoCodec:"h264",audioCodec:"aac",pixelFormat:"yuv420p",videoBitrate:1_000_000,audioBitrate:120_000,driveID:"fixture",driveURL:"https://drive.google.com/file/d/fixture/view",directURL:"https://drive.google.com/uc?export=download&id=fixture",technicalChecks:["fixture":"Not live evidence"],urlEvidence:url,capabilityEvidence:profile,warnings:["Isolated fixture only"])
        return BufferPreparedClip(jobID:"fixture-job",clipID:id,lane:"taxstone",sourceID:"soundcloud:fixture",episode:"Fixture episode",intervals:[Interval(Double(id-1)*10,Double(id)*10)],sha256:sha,rightsBasis:"Isolated test",recommendation:recommendation,media:media,checkedAt:now,error:nil)
    }
    private func receipt(_ batch: BufferManifest,operation: BufferOperation) -> BufferReceipt {
        BufferReceipt(batchID:batch.id,manifestSHA256:batch.manifestSHA256,operationID:operation.id,jobID:operation.clip.jobID,clipID:operation.clip.clipID,sourceID:operation.clip.sourceID,lane:operation.clip.lane,platform:operation.platform,organizationID:operation.channel!.organizationID,channelID:operation.channel!.channelID,postID:"fixture-post-"+operation.platform.rawValue,requestedMode:.draft,providerState:.draft,mediaReference:operation.clip.media!.directURL,submittedAt:Date(),readbackAt:Date(),errors:[],verificationMethod:"Isolated fixture readback, not live Buffer",reconciliationState:.reconciled)
    }
    func testOperationIdentityBindsExactIntervalsHashLaneAndChannel() throws {
        let a = try BufferOperation.identity(lane:"taxstone",sourceID:"soundcloud:1",intervals:[Interval(0.125,10.625)],sha256:String(repeating:"a",count:64),platform:.x,channelID:"tax-x")
        let same = try BufferOperation.identity(lane:"taxstone",sourceID:"soundcloud:1",intervals:[Interval(0.125,10.625)],sha256:String(repeating:"a",count:64),platform:.x,channelID:"tax-x")
        XCTAssertEqual(a,same)
        for b in [
            try BufferOperation.identity(lane:"taxstone",sourceID:"soundcloud:1",intervals:[Interval(0.126,10.625)],sha256:String(repeating:"a",count:64),platform:.x,channelID:"tax-x"),
            try BufferOperation.identity(lane:"dub",sourceID:"soundcloud:1",intervals:[Interval(0.125,10.625)],sha256:String(repeating:"a",count:64),platform:.x,channelID:"tax-x"),
            try BufferOperation.identity(lane:"taxstone",sourceID:"soundcloud:1",intervals:[Interval(0.125,10.625)],sha256:String(repeating:"b",count:64),platform:.x,channelID:"tax-x"),
            try BufferOperation.identity(lane:"taxstone",sourceID:"soundcloud:1",intervals:[Interval(0.125,10.625)],sha256:String(repeating:"a",count:64),platform:.instagram,channelID:"tax-ig")
        ] {XCTAssertNotEqual(a,b)}
    }

    func testAuthorizationMustBeSeparateExactAndUnexpired() throws {
        let now = Date()
        let grant = BufferExecutionAuthorization(batchID:"batch",operationIDs:["one"],channelIDs:["tax-x"],mode:.draft,expiresAt:now.addingTimeInterval(300),actualUserRequest:"Frank explicitly authorizes batch, one, tax-x, drafts only")
        XCTAssertNoThrow(try grant.validate(batchID:"batch",operationID:"one",channelID:"tax-x",mode:.draft,now:now))
        XCTAssertThrowsError(try grant.validate(batchID:"batch",operationID:"one",channelID:"tax-x",mode:.queue,now:now))
        XCTAssertThrowsError(try grant.validate(batchID:"other",operationID:"one",channelID:"tax-x",mode:.draft,now:now))
        XCTAssertThrowsError(try grant.validate(batchID:"batch",operationID:"two",channelID:"tax-x",mode:.draft,now:now))
        XCTAssertThrowsError(try grant.validate(batchID:"batch",operationID:"one",channelID:"dub-x",mode:.draft,now:now))
        XCTAssertThrowsError(try grant.validate(batchID:"batch",operationID:"one",channelID:"tax-x",mode:.draft,now:now.addingTimeInterval(301)))
    }

    func testRateGateHonorsAllWindowsRetryAfterAndUncertainWrites() {
        let now = Date()
        func check(_ remaining: [Int],attempts: Int = 0,retry: Double = 0,uncertain: Bool = false) -> BufferRetryDecision {
            BufferRateGate.decide(remainingAllowances:remaining,observedAt:now,now:now,attempts:attempts,retryAfter:now.addingTimeInterval(retry),authorizationExpiresAt:now.addingTimeInterval(120),uncertainWrite:uncertain)
        }
        XCTAssertEqual(check([100,500,5000]),.proceed)
        XCTAssertEqual(check([100,0,5000]),.stop("Request allowance exhausted"))
        XCTAssertEqual(check([100,500,0]),.stop("Request allowance exhausted"))
        XCTAssertEqual(check([100],attempts:3),.stop("Three transient attempts exhausted"))
        XCTAssertEqual(check([100],retry:30),.waitUntil(now.addingTimeInterval(30)))
        XCTAssertEqual(check([100],retry:130),.stop("Authorization expires before retry"))
        XCTAssertEqual(check([100],uncertain:true),.reconcile)
        XCTAssertEqual(check([]),.stop("Current rate-limit evidence required"))
    }

    func testInstagramNeedsExplicitSupportedPresentationAndScheduleLongevity() {
        var options = BufferSelection()
        options.platforms = [.x,.instagram]
        XCTAssertTrue(options.blockers(for:.x).isEmpty)
        XCTAssertFalse(options.blockers(for:.instagram).isEmpty)
        options.instagramPresentation = .reelSharedToFeed
        options.instagramAcknowledged = true
        XCTAssertTrue(options.blockers(for:.instagram).isEmpty)
        options.instagramPresentation = .traditionalFeed
        XCTAssertFalse(options.blockers(for:.instagram).isEmpty)
        options.mode = .queue
        XCTAssertFalse(options.blockers(for:.x).isEmpty,"Queue needs retrieval-lifetime evidence, not just a working URL now")
    }
}
