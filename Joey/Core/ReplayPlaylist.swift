import Foundation

/// Resolves an ended replay's duration without downloading its media segments.
enum ReplayPlaylist {
    static let maximumBytes = 4 * 1024 * 1024

    static func allowedURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil,
              url.path.lowercased().hasSuffix(".m3u8"), let host = url.host?.lowercased() else {return false}
        return host == "video.twimg.com" || host == "video.pscp.tv" || host.hasSuffix(".video.pscp.tv")
    }

    static func load(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        guard allowedURL(url) else {throw JoeyError.invalid("Unsafe X replay playlist URL")}
        try Task.checkCancellation()
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil; configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        var request = URLRequest(url:url)
        request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL",forHTTPHeaderField:"Accept")
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        let (stream,response) = try await session.bytes(for:request,delegate:ReplayPlaylistRedirects())
        guard let http = response as? HTTPURLResponse else {throw JoeyError.dependency("X replay playlist response was not HTTP")}
        guard http.statusCode == 200 else {throw JoeyError.dependency("X replay playlist HTTP \(http.statusCode)")}
        guard let finalURL = http.url, allowedURL(finalURL),
              http.expectedContentLength <= Int64(maximumBytes) else {
            throw JoeyError.dependency("X replay playlist was unavailable, redirected unsafely, or exceeded its size limit")
        }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < maximumBytes else {throw JoeyError.dependency("X replay playlist exceeded its size limit")}
            data.append(byte)
        }
        return data
    }

    static func duration(_ data: Data) throws -> Double {
        guard data.count <= maximumBytes, let text = String(data:data,encoding:.utf8) else {
            throw JoeyError.dependency("X replay playlist is oversized or not UTF-8")
        }
        let lines = text.components(separatedBy:.newlines).map {$0.trimmingCharacters(in:.whitespaces)}.filter {!$0.isEmpty}
        guard lines.first == "#EXTM3U" else {throw JoeyError.dependency("X replay response is not an HLS playlist")}
        var pending: Double?, total = 0.0, segments = 0, ended = false
        for line in lines.dropFirst() {
            guard !ended else {throw JoeyError.dependency("X replay playlist continues after ENDLIST")}
            if line == "#EXT-X-ENDLIST" {
                guard pending == nil else {throw JoeyError.dependency("X replay playlist has a missing final segment")}
                ended = true
            } else if line.hasPrefix("#EXTINF:") {
                let raw = line.dropFirst(8).split(separator:",",omittingEmptySubsequences:false)[0]
                guard pending == nil, let value = Double(raw), value.isFinite, value > 0 else {
                    throw JoeyError.dependency("X replay playlist has an invalid segment duration")
                }
                pending = value
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                guard Int(line.dropFirst(22)) == 0 else {throw JoeyError.dependency("X replay playlist omits its beginning")}
            } else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                guard ["VOD","EVENT"].contains(String(line.dropFirst(21))) else {
                    throw JoeyError.dependency("X replay playlist has an unsupported type")
                }
            } else if ["#EXT-X-STREAM-INF", "#EXT-X-I-FRAMES-ONLY", "#EXT-X-GAP", "#EXT-X-SKIP", "#EXT-X-PART", "#EXT-X-PRELOAD-HINT"].contains(where:{line.hasPrefix($0)}) {
                throw JoeyError.dependency("X replay playlist is partial, missing segments, or not a media playlist")
            } else if !line.hasPrefix("#") {
                guard let value = pending else {throw JoeyError.dependency("X replay segment lacks a duration")}
                total += value; segments += 1; pending = nil
            }
        }
        guard ended, pending == nil, segments > 0, total.isFinite, total > 0, total < 1_000_000 else {
            throw JoeyError.dependency("X replay playlist is unfinished, empty, or has an invalid duration")
        }
        return total
    }
}

private final class ReplayPlaylistRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirects = 0

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); redirects += 1; let count = redirects; lock.unlock()
        guard count <= 3, let url = request.url, ReplayPlaylist.allowedURL(url) else {completionHandler(nil); return}
        var clean = URLRequest(url:url)
        clean.setValue("application/vnd.apple.mpegurl, application/x-mpegURL",forHTTPHeaderField:"Accept")
        clean.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        completionHandler(clean)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling,nil)
        } else {completionHandler(.cancelAuthenticationChallenge,nil)}
    }
}
