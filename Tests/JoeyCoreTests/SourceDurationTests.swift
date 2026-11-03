import XCTest
@testable import JoeyCore

final class SourceDurationTests: XCTestCase {
    private let sourceURL = "https://x.com/i/broadcasts/fixtureReplay123"
    private let playlistURL = "https://prod-fastly-p.video.pscp.tv/synthetic/replay.m3u8"
    private let playlist = """
    #EXTM3U
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-TARGETDURATION:7
    #EXTINF:6.250,
    first.ts
    #EXTINF:2.125,
    last.ts
    #EXT-X-ENDLIST
    """

    private func metadata(_ changes: [String:Any] = [:]) throws -> Data {
        var value: [String:Any] = [
            "id":"fixtureReplay123", "title":"Synthetic ended replay", "duration":NSNull(),
            "is_live":false, "live_status":"was_live",
            "formats":[["format_id":"replay", "protocol":"m3u8_native", "url":playlistURL]]
        ]
        value.merge(changes) { _, new in new }
        return try JSONSerialization.data(withJSONObject:value)
    }

    func testEndedXReplayResolvesMissingDuration() async throws {
        let source = try await SourceDiscovery.parseSource(metadata(),url:sourceURL) { _ in Data(self.playlist.utf8) }
        XCTAssertEqual(source.id,"x:broadcast:fixtureReplay123")
        XCTAssertEqual(source.duration,8.375,accuracy:0.000001)
    }

    func testEndedXSpaceResolvesMissingDuration() async throws {
        let source = try await SourceDiscovery.parseSource(metadata(),url:"https://x.com/i/spaces/fixtureReplay123") { _ in
            Data(self.playlist.utf8)
        }
        XCTAssertEqual(source.id,"x:space:fixtureReplay123")
        XCTAssertEqual(source.duration,8.375,accuracy:0.000001)
    }

    func testKnownMetadataDurationNeedsNoPlaylist() async throws {
        let source = try await SourceDiscovery.parseSource(metadata(["duration":3600,"upload_date":"20261103"]),url:sourceURL) { _ in
            XCTFail("A valid metadata duration must not require another network request")
            throw JoeyError.failed("Unexpected playlist request")
        }
        XCTAssertEqual(source.duration,3600)
        XCTAssertEqual(source.episodeDate,"2026-11-03")
        let youtube = try await SourceDiscovery.parseSource(metadata(["id":"abcdefghijk","duration":1200]),
            url:"https://www.youtube.com/watch?v=abcdefghijk")
        XCTAssertEqual(youtube.id,"youtube:abcdefghijk")
        XCTAssertEqual(youtube.duration,1200)
    }

    func testUnfinishedSourcesRejectedBeforePlaylistFetch() async throws {
        for changes: [String:Any] in [["is_live":true],["live_status":"is_live"],["live_status":"post_live"],
                                    ["live_status":"is_upcoming"],["live_status":"not_live"],["is_live":NSNull()]] {
            do {
                _ = try await SourceDiscovery.parseSource(metadata(changes),url:sourceURL) { _ in
                    XCTFail("Unfinished or unconfirmed live metadata must not fetch a replay")
                    return Data(self.playlist.utf8)
                }
                XCTFail("Unfinished source accepted: \(changes)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }

    func testIdentityMismatchRejectedBeforePlaylistFetch() async throws {
        do {
            _ = try await SourceDiscovery.parseSource(metadata(["id":"differentSource"]),url:sourceURL) { _ in
                XCTFail("Mismatched metadata must not fetch a playlist")
                return Data(self.playlist.utf8)
            }
            XCTFail("Mismatched source accepted")
        } catch {XCTAssertTrue(error.localizedDescription.contains("identity"))}
    }

    func testFallbackCannotAuthorizeOtherSourceTypesOrInvalidDurations() async throws {
        for url in ["https://x.com/fixture/status/fixtureReplay123","https://www.youtube.com/watch?v=abcdefghijk"] {
            do {
                let id = url.contains("youtube") ? "abcdefghijk" : "fixtureReplay123"
                _ = try await SourceDiscovery.parseSource(metadata(["id":id]),url:url) { _ in
                    XCTFail("Unsupported source must not use the replay fallback")
                    return Data(self.playlist.utf8)
                }
                XCTFail("Missing-duration fallback accepted an unsupported source")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
        for duration: Any in [0,-1,true,"8.375",1e20] {
            do {
                _ = try await SourceDiscovery.parseSource(metadata(["duration":duration]),url:sourceURL) { _ in
                    XCTFail("An explicitly invalid duration must not be silently replaced")
                    return Data(self.playlist.utf8)
                }
                XCTFail("Invalid metadata duration accepted: \(duration)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }

    func testIncompleteOrMalformedPlaylistsCannotResolveDuration() async throws {
        let invalid = [
            playlist.replacingOccurrences(of:"#EXT-X-ENDLIST",with:""),
            playlist.replacingOccurrences(of:"#EXT-X-MEDIA-SEQUENCE:0",with:"#EXT-X-MEDIA-SEQUENCE:8"),
            playlist.replacingOccurrences(of:"#EXT-X-MEDIA-SEQUENCE:0",with:"#EXT-X-MEDIA-SEQUENCE:invalid"),
            playlist.replacingOccurrences(of:"#EXTINF:6.250,",with:"#EXTINF:nan,"),
            playlist.replacingOccurrences(of:"#EXTINF:6.250,",with:"#EXTINF:inf,"),
            playlist.replacingOccurrences(of:"#EXTINF:6.250,",with:"#EXTINF:0,"),
            playlist.replacingOccurrences(of:"last.ts",with:""),
            playlist.replacingOccurrences(of:"#EXTINF:6.250,",with:""),
            playlist.replacingOccurrences(of:"first.ts",with:"#EXT-X-GAP\nfirst.ts"),
            playlist.replacingOccurrences(of:"first.ts",with:"#EXT-X-SKIP:SKIPPED-SEGMENTS=1\nfirst.ts"),
            playlist.replacingOccurrences(of:"first.ts",with:"#EXT-X-PART:DURATION=1,URI=\"part.ts\"\nfirst.ts"),
            playlist + "\n#EXTINF:1,\nextra.ts",
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nvariant.m3u8\n#EXT-X-ENDLIST",
            "#EXTM3U\n#EXT-X-ENDLIST",
            "<html>sign in</html>"
        ]
        for (index,text) in invalid.enumerated() {
            do {
                _ = try await SourceDiscovery.parseSource(metadata(),url:sourceURL) { _ in Data(text.utf8) }
                XCTFail("Incomplete/malformed playlist accepted: case \(index)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }

    func testUnsafePlaylistReferencesRejectedBeforeFetch() async throws {
        for raw in ["http://prod-fastly-p.video.pscp.tv/replay.m3u8","https://localhost/replay.m3u8",
                    "https://video.twimg.com.evil.test/replay.m3u8","https://user:password@video.twimg.com/replay.m3u8",
                    "https://video.twimg.com:8080/replay.m3u8","https://video.twimg.com/media.mp4"] {
            do {
                _ = try await SourceDiscovery.parseSource(metadata(["formats":[["protocol":"m3u8_native","url":raw]]]),url:sourceURL) { _ in
                    XCTFail("Unsafe playlist URL reached the network boundary")
                    return Data(self.playlist.utf8)
                }
                XCTFail("Unsafe playlist accepted: \(raw)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }

    private func request() throws -> JobRequest {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:directory)}
        var request = try Fixtures.request(dir:directory,path:"unused")
        request.localPath = nil; request.originalURL = sourceURL; request.sourceID = "x:broadcast:fixtureReplay123"
        return request
    }

    func testAcquisitionUsesReplayDurationAndRejectsShortDownload() async throws {
        let source = try await Acquisition.sourceMetadata(metadata(),request:request()) { _ in Data(self.playlist.utf8) }
        XCTAssertEqual(source.duration,8.375,accuracy:0.000001)
        XCTAssertNoThrow(try Acquisition.validateDownloadedDuration(8.375,expected:source.duration))
        for measured in [6.375,12,0,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try Acquisition.validateDownloadedDuration(measured,expected:source.duration))
        }
        let arguments = Acquisition.downloadArguments(for:URL(string:sourceURL)!,directory:URL(fileURLWithPath:"/synthetic"))
        XCTAssertTrue(arguments.contains("--abort-on-unavailable-fragments"),"A missing fragment must fail the downloader rather than be skipped")
    }

    func testAcquisitionRejectsMismatchedRequestAndPostLiveSource() async throws {
        var request = try request(); request.sourceID = "x:broadcast:differentSource"
        do {
            _ = try await Acquisition.sourceMetadata(metadata(),request:request) { _ in
                XCTFail("Mismatched request must fail before network access")
                return Data(self.playlist.utf8)
            }
            XCTFail("Mismatched acquisition request accepted")
        } catch {XCTAssertTrue(error.localizedDescription.contains("identity"))}
        request.sourceID = "x:broadcast:fixtureReplay123"
        do {
            _ = try await Acquisition.sourceMetadata(metadata(["duration":8.375,"live_status":"post_live"]),request:request)
            XCTFail("Post-live processing source accepted")
        } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
    }

    func testAcquisitionPreservesLegacyProviderIDPrefixes() async throws {
        var request = try request()
        for id in ["fixtureReplay123","legacy-fixtureReplay123","legacy:fixtureReplay123","x:broadcast:fixtureReplay123"] {
            request.sourceID = id
            let source = try await Acquisition.sourceMetadata(metadata(["duration":8.375]),request:request)
            XCTAssertEqual(source.id,"x:broadcast:fixtureReplay123")
            XCTAssertEqual(source.duration,8.375)
        }
    }

    func testTransientPlaylistFailureRetriesWithoutReplacingItsDuration() async throws {
        var attempts = 0
        let source = try await SourceDiscovery.parseSource(metadata(),url:sourceURL) { _ in
            attempts += 1
            if attempts < 3 {throw JoeyError.dependency("X replay playlist HTTP 503")}
            return Data(self.playlist.utf8)
        }
        XCTAssertEqual(source.duration,8.375)
        XCTAssertEqual(attempts,3)
        attempts = 0
        do {
            _ = try await SourceDiscovery.parseSource(metadata(),url:sourceURL) { _ in
                attempts += 1
                throw JoeyError.dependency("X replay playlist HTTP 503")
            }
            XCTFail("Persistent playlist failure was accepted")
        } catch {XCTAssertEqual(attempts,3,"Transient retries must stop after three attempts")}
    }

    func testCancellationPropagatesFromPlaylistFetch() async throws {
        do {
            _ = try await SourceDiscovery.parseSource(metadata(),url:sourceURL) { _ in throw CancellationError() }
            XCTFail("Cancellation was swallowed")
        } catch is CancellationError {} catch {XCTFail("Cancellation changed to \(error)")}
    }

    func testPlaylistHTTPFetchIsBoundedAndCredentialFree() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplayHTTPProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization":"synthetic-canary","Cookie":"synthetic-canary"]
        ReplayHTTPProtocol.body = Data(playlist.utf8)
        let bytes = try await ReplayPlaylist.load(URL(string:playlistURL)!,configuration:configuration)
        XCTAssertEqual(try ReplayPlaylist.duration(bytes),8.375,accuracy:0.000001)
        for path in ["missing.m3u8","html.m3u8","oversized-header.m3u8","oversized-body.m3u8"] {
            do {
                let url = URL(string:"https://video.twimg.com/"+path)!
                let bytes = try await ReplayPlaylist.load(url,configuration:configuration)
                _ = try ReplayPlaylist.duration(bytes)
                XCTFail("Invalid HTTP playlist accepted: \(path)")
            } catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
        }
    }
}

private final class ReplayHTTPProtocol: URLProtocol {
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        guard request.value(forHTTPHeaderField:"Authorization") == nil, request.value(forHTTPHeaderField:"Cookie") == nil else {
            client?.urlProtocol(self,didFailWithError:JoeyError.failed("Playlist request leaked a credential canary")); return
        }
        let path = request.url!.lastPathComponent
        let data = path == "html.m3u8" ? Data("<html>sign in</html>".utf8) :
            (path == "oversized-body.m3u8" ? Data(repeating:65,count:4_194_305) : Self.body)
        let headers = path == "oversized-header.m3u8" ? ["Content-Length":"4194305"] : [:]
        let response = HTTPURLResponse(url:request.url!,statusCode:path == "missing.m3u8" ? 404 : 200,httpVersion:nil,headerFields:headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
