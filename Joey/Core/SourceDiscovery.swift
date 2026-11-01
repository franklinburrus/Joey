import Foundation

public struct DiscoveredSource: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var duration: Double
    public var channelID: String?
    public var episodeDate: String?
    public var episodeNumber: Int?
}

public enum SourceDiscovery {
    public static let joeChannelID = "UC23_r1bpkTWaBltbXsQxysA"
    public static let joeChannelURL = "https://www.youtube.com/channel/" + joeChannelID + "/videos"
    public static func episodeNumber(_ title: String) -> Int? {
        let expression = try! NSRegularExpression(pattern: "^(?:The )?Joe Budden Podcast (?:Episode|Ep\\.?)\\s+(\\d+)\\s*(?:\\||:|$)", options:.caseInsensitive)
        guard let match = expression.firstMatch(in:title,range:NSRange(title.startIndex...,in:title)),
              let range = Range(match.range(at:1),in:title) else {return nil}
        return Int(title[range])
    }
    static func command(_ arguments: [String]) async throws -> Data {
        try await withThrowingTaskGroup(of:Data.self) { group in
            group.addTask {
                try await Processes.run("yt-dlp",["--ignore-config","--socket-timeout","15","--retries","1","--extractor-retries","1"]+arguments,maxOutput:4*1024*1024).stdout
            }
            group.addTask {
                try await Task.sleep(nanoseconds:60_000_000_000)
                throw JoeyError.dependency("YouTube/source lookup timed out. Check connectivity and retry.")
            }
            defer {group.cancelAll()}
            return try await group.next()!
        }
    }
    public static func lookup(_ raw: String) async throws -> DiscoveredSource {
        let url = try Acquisition.validateOriginalURL(raw)
        let data = try await command(["--no-playlist","--skip-download","--dump-single-json",url.absoluteString])
        return try parseSource(data,url:url.absoluteString)
    }
    static func parseSource(_ data: Data, url: String) throws -> DiscoveredSource {
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let id = object["id"] as? String, !id.isEmpty,
              let title = object["title"] as? String, !title.isEmpty,
              let duration = object["duration"] as? Double, duration.isFinite, duration > 0,
              object["is_live"] as? Bool != true,
              !["is_live","is_upcoming","post_live"].contains(object["live_status"] as? String ?? "") else {
            throw JoeyError.dependency("The source is unfinished, unavailable, or lacks a complete duration and identity")
        }
        guard let sourceID = SourceIdentitySuggestion.from(url), sourceID.hasSuffix(":"+id) else {
            throw JoeyError.invalid("Source link and provider identity do not match")
        }
        let rawDate = object["upload_date"] as? String
        let date: String?
        if let rawDate, rawDate.range(of:"^[0-9]{8}$",options:.regularExpression) != nil {
            date = String(rawDate.prefix(4))+"-"+String(rawDate.dropFirst(4).prefix(2))+"-"+String(rawDate.suffix(2))
        } else {date = nil}
        return DiscoveredSource(id:sourceID,title:title,url:url,duration:duration,
            channelID:object["channel_id"] as? String,episodeDate:date,episodeNumber:episodeNumber(title))
    }
    public static func recentJoeEpisodes() async throws -> [DiscoveredSource] {
        try parseJoeFeed(await command(["--flat-playlist","--playlist-end","30","--skip-download","--dump-single-json",joeChannelURL]))
    }
    static func parseJoeFeed(_ data: Data) throws -> [DiscoveredSource] {
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              object["channel_id"] as? String == joeChannelID,
              let entries = object["entries"] as? [[String:Any]] else {throw JoeyError.failed("Joe Budden feed identity could not be verified")}
        var seen = Set<String>()
        return entries.compactMap { item in
            guard let id = item["id"] as? String, id.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil,
                  let title = item["title"] as? String, let number = episodeNumber(title),
                  let duration = item["duration"] as? Double, duration.isFinite, duration > 0,
                  item["is_live"] as? Bool != true,
                  !["is_live","is_upcoming","post_live"].contains(item["live_status"] as? String ?? ""),
                  seen.insert(id).inserted else {return nil}
            return DiscoveredSource(id:"youtube:"+id,title:title,url:"https://www.youtube.com/watch?v="+id,
                duration:duration,channelID:joeChannelID,episodeNumber:number)
        }.sorted {($0.episodeNumber ?? 0) > ($1.episodeNumber ?? 0)}
    }
}
