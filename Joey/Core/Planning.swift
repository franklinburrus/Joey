import Foundation

public struct Interval: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(_ start: Double, _ end: Double) { self.start = start; self.end = end }
    public var duration: Double { end - start }
}

public enum Planning {
    public static let tolerance = 0.000001
    public static func retained(duration: Double, exclusions: [Interval]) throws -> [Interval] {
        guard duration.isFinite, duration > 0 else { throw JoeyError.invalid("Source duration must be finite and positive") }
        var cursor = 0.0
        var result: [Interval] = []
        for item in exclusions.sorted(by: { $0.start < $1.start }) {
            guard item.start.isFinite, item.end.isFinite, item.start >= cursor,
                  item.end > item.start, item.end <= duration else {
                throw JoeyError.invalid("Invalid, overlapping or out-of-source exclusion")
            }
            if item.start > cursor { result.append(Interval(cursor, item.start)) }
            cursor = item.end
        }
        if cursor < duration { result.append(Interval(cursor, duration)) }
        guard !result.isEmpty else { throw JoeyError.invalid("No retained program content") }
        return result
    }
    public static func fullShow(duration: Double, exclusions: [Interval] = [], limit: Double = 600,
                                boundaries: [Double] = []) throws -> [[Interval]] {
        guard limit.isFinite, limit > 0 else { throw JoeyError.invalid("Invalid platform duration limit") }
        let ranges = try retained(duration: duration, exclusions: exclusions)
        let total = ranges.reduce(0) { $0 + $1.duration }
        let target = min(600, limit)
        var timelineBoundaries: [Double] = []
        var offset = 0.0
        for range in ranges {
            timelineBoundaries += boundaries.filter { $0.isFinite && $0 >= range.start && $0 <= range.end }
                .map { offset + $0 - range.start }
            offset += range.duration
        }
        var cursor = 0.0
        var clips: [[Interval]] = []
        while cursor < total {
            var end = min(cursor + target, total)
            if end < total, let natural = timelineBoundaries.filter({
                $0 >= cursor + min(480, target * 0.8) && $0 <= end
            }).max() { end = natural }
            var position = 0.0
            var clip: [Interval] = []
            for range in ranges {
                let a = max(cursor, position), b = min(end, position + range.duration)
                if b > a { clip.append(Interval(range.start + a - position, range.start + b - position)) }
                position += range.duration
            }
            guard !clip.isEmpty, end > cursor else { throw JoeyError.invalid("Planner made no progress") }
            clips.append(clip)
            cursor = end
        }
        try validateCoverage(duration: duration, exclusions: exclusions, clips: clips)
        return clips
    }
    public static func validateCoverage(duration: Double, exclusions: [Interval], clips: [[Interval]]) throws {
        let expected = try retained(duration: duration, exclusions: exclusions)
        guard !clips.isEmpty, clips.allSatisfy({ !$0.isEmpty }) else { throw JoeyError.invalid("Empty clip coverage") }
        var merged: [Interval] = []
        for interval in clips.flatMap({ $0 }) {
            guard interval.start.isFinite, interval.end.isFinite, interval.duration > 0,
                  interval.start >= 0, interval.end <= duration + tolerance else {
                throw JoeyError.invalid("Invalid clip interval")
            }
            if var previous = merged.last {
                guard interval.start >= previous.end - tolerance else { throw JoeyError.invalid("Duplicated or reordered coverage") }
                if abs(interval.start - previous.end) <= tolerance {
                    previous.end = interval.end; merged[merged.count-1] = previous; continue
                }
            }
            merged.append(interval)
        }
        guard expected.count == merged.count, zip(expected,merged).allSatisfy({
            abs($0.start - $1.start) <= tolerance && abs($0.end - $1.end) <= tolerance
        }) else { throw JoeyError.invalid("Retained program content has gaps or excluded content is present") }
    }
}
