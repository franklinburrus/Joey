import Foundation

public enum Editorial {
    public static func planWithoutTranscript(request: JobRequest, source: SourceRecord) throws -> [ClipRecord] {
        guard request.transcriptPolicy == .modelIndependent, request.mode == .fullShow,
              request.adExclusions.isEmpty else {throw JoeyError.invalid("Time-based local planning requires full coverage without exclusions")}
        let policy = DurationPolicy(profile:request.profile)
        return try Planning.fullShow(duration:source.duration,limit:policy.plannedMaximum,preferredDuration:request.preferredDuration ?? 600,minimumDuration:policy.minimum).enumerated().map { index, intervals in
            let sequence = String(format:"%02d",index+1)
            let duration = intervals.reduce(0) {$0+$1.duration}
            return ClipRecord(id:index+1,title:"Part "+sequence,intervals:intervals,
                filename:sequence+"_Part_"+sequence+"_"+Persistence.safeName(source.id)+"_"+stamp(intervals.first!.start)+"_to_"+stamp(intervals.last!.end)+".mp4",
                durationException:duration < 480 ? "Short source, retained remainder, or shared duration limit" : nil)
        }
    }
    public static func exclusions(_ request: JobRequest, transcript: Transcript) -> [AdExclusion] {
        guard request.mode == .fullShow else { return [] }
        // An explicit ad start AND explicit return to the program are required.
        // Mere brand names, links, uncertain promotions and unbounded reads stay.
        var found = request.adExclusions.filter { $0.confidence >= 0.99 && !$0.evidence.isEmpty }
        var start: TranscriptSegment?
        for segment in transcript.segments {
            let text = segment.text.lowercased()
            if start == nil && (text.contains("this episode is sponsored by") || text.contains("this is a paid advertisement")) { start = segment }
            if let opening = start, text.contains("back to the show") || text.contains("back to the episode") {
                if segment.start > opening.start && segment.start-opening.start <= 300 {
                    let range = Interval(opening.start,segment.start)
                    if !found.contains(where: { $0.interval.start < range.end && $0.interval.end > range.start }) {
                        found.append(AdExclusion(interval:range,evidence:"Transcript: \(opening.text) … \(segment.text)",confidence:0.99))
                    }
                }
                start = nil
            }
            if let opening = start, segment.end-opening.start > 300 { start = nil }
        }
        return found.sorted { $0.interval.start < $1.interval.start }
    }
    public static func plan(request: JobRequest, source: SourceRecord, transcript: Transcript, exclusions: [AdExclusion]) throws -> [ClipRecord] {
        let ranges: [[Interval]]
        let policy = DurationPolicy(profile:request.profile)
        let limit = request.productionWorkflow == .joeBudden ? 600 : policy.plannedMaximum
        if request.mode == .fullShow {
            ranges = try Planning.fullShow(duration:source.duration,exclusions:exclusions.map(\.interval),limit:limit,
                boundaries:transcript.segments.filter { ".!?".contains($0.text.last ?? " ") }.map(\.end),preferredDuration:request.preferredDuration ?? 600,minimumDuration:policy.minimum)
        } else if let fixed = request.fixedIntervals {
            guard !fixed.isEmpty, request.requestedCount == nil || fixed.count == request.requestedCount else { throw JoeyError.invalid("Fixed selections conflict with requested highlight count") }
            ranges = fixed.map { [$0] }
        } else {
            if request.productionWorkflow == .link {
                let count = try Planning.highlightCount(duration:source.duration)
                ranges = (0..<count).map { index in
                    let blockStart = Double(index)*900, blockEnd = min(source.duration,blockStart+900)
                    // A short final block may borrow preceding unselected content;
                    // keep its ending and count without emitting an invalid fragment.
                    let start = max(0,min(blockStart,blockEnd-policy.minimum))
                    // One chronological selection per source block. Prefer a
                    // sentence endpoint without crossing the block or hard limit.
                    let end = min(blockEnd,start+min(limit,600))
                    let boundary = transcript.segments.filter { $0.end > start && $0.end <= end && $0.end >= start+(end-start)*0.8 && ".!?".contains($0.text.last ?? " ") }.map(\.end).max()
                    return [Interval(start,boundary ?? end)]
                }
            } else {
                let candidates = try Planning.fullShow(duration:source.duration,limit:min(limit,120),boundaries:transcript.segments.map(\.end),minimumDuration:policy.minimum)
                let count = request.requestedCount ?? min(10,candidates.count)
                guard count <= candidates.count else { throw JoeyError.invalid("Requested \(count) self-contained highlights; only \(candidates.count) nonoverlapping candidate segments fit") }
                ranges = (0..<count).map { candidates[$0*candidates.count/count] }
            }
        }
        var lastEnd = 0.0
        return try ranges.enumerated().map { index, intervals in
            guard let first = intervals.first, let last = intervals.last,
                  first.start >= lastEnd, last.end <= source.duration, intervals.allSatisfy({$0.start.isFinite && $0.end.isFinite && $0.duration > 0}) else { throw JoeyError.invalid("Invalid, overlapping or out-of-source highlight interval") }
            let duration = intervals.reduce(0) {$0+$1.duration}
            try policy.validatePlanned(duration)
            guard duration <= limit+Planning.tolerance else { throw JoeyError.invalid("Fixed interval \(first.start)–\(last.end) is \(duration)s; verified shared limit is \(limit)s") }
            lastEnd = last.end
            let quote = transcript.segments.first { s in intervals.contains { s.start >= $0.start && s.end <= $0.end } }?.text
            let title = quote.map { String($0.split(separator:" ").prefix(12).joined(separator:" ")) } ?? "\(source.title) — Part \(index+1)"
            let filename = String(format:"%02d",index+1)+"_"+Persistence.safeName(title)+"_"+Persistence.safeName(source.id)+"_"+stamp(first.start)+"_to_"+stamp(last.end)+".mp4"
            return ClipRecord(id:index+1,title:title,intervals:intervals,filename:filename,
                durationException:duration < 480 ? (limit < 480 ? "Verified platform duration limit" : "Short source, retained remainder, or explicit highlight") : nil)
        }
    }
    public static func stamp(_ seconds: Double) -> String {
        let n = Int(max(0,seconds)); return String(format:"%02d-%02d-%02d",n/3600,(n/60)%60,n%60)
    }
}
