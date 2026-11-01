import Foundation

/// Distribution metadata only. These recommendations never alter an accepted production plan or file.
public struct ClipRecommendation: Codable, Equatable, Sendable {
    public var title: String
    public var topic: String
    public var xCaption: String
    public var instagramCaption: String
    public var xScore: Int
    public var instagramScore: Int
    public var rationale: [String]
    public var confidence: String
    public var boundaryNotes: [String]
    public var restrictions: [String]
    public var transcriptEvidence: [TranscriptSegment]
}

/// A bounded, deterministic fallback when model-assisted editorial ranking is unavailable.
/// All content analysis is local string processing; no model, filesystem or network access occurs.
public enum ClipIntelligence {
    public static func evaluate(job: JobRecord, clip: ClipRecord) throws -> ClipRecommendation {
        guard job.state == .completed, clip.id > 0,
              job.clips.filter({ $0.id == clip.id }).count == 1,
              job.clips.contains(clip) else {
            throw JoeyError.invalid("Clip Intelligence requires an unchanged clip from a completed job")
        }
        guard let source = job.source, source.id == job.request.sourceID,
              source.owner == job.request.owner, source.duration.isFinite, source.duration > 0,
              !source.sha256.isEmpty else {
            throw JoeyError.invalid("Clip Intelligence source identity does not match the job")
        }
        guard let hash = clip.sha256, !hash.isEmpty, let qa = clip.qa, qa.passed,
              qa.outputSHA256 == hash, let duration = clip.measuredDuration,
              duration.isFinite, duration > 0, (clip.bytes ?? 0) > 0 else {
            throw JoeyError.invalid("Clip Intelligence requires accepted media with matching QA identity")
        }
        guard let transcript = job.transcript, job.planningBasis != .deterministicTime else {
            throw JoeyError.dependency("Clip Intelligence requires the source-bound production transcript")
        }
        try transcript.validate(sourceID: source.id, sha256: source.sha256, duration: source.duration)
        // Overlapping transcript segments cannot establish unambiguous clip-local textual evidence.
        var previousEnd = 0.0
        for segment in transcript.segments {
            guard segment.start >= previousEnd, segment.end > segment.start,
                  !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw JoeyError.invalid("Clip Intelligence requires nonoverlapping timestamped transcript segments")
            }
            previousEnd = segment.end
        }
        guard !clip.intervals.isEmpty else { throw JoeyError.invalid("Clip has no source intervals") }
        previousEnd = 0
        for interval in clip.intervals {
            guard interval.start.isFinite, interval.end.isFinite, interval.start >= previousEnd,
                  interval.end > interval.start, interval.end <= source.duration else {
                throw JoeyError.invalid("Clip Intelligence found invalid or overlapping source intervals")
            }
            previousEnd = interval.end
        }

        // A segment crossing a cut may contain words absent from the delivered media. Never use its
        // text to invent an in-clip quote, topic or caption. Excluded intervals are treated identically.
        let evidence = transcript.segments.filter { segment in
            clip.intervals.contains { segment.start >= $0.start && segment.end <= $0.end }
        }
        let words = evidence.flatMap { tokens($0.text) }
        guard words.count >= 6, let opening = evidence.first else {
            throw JoeyError.dependency("Insufficient fully contained transcript evidence for this clip")
        }
        let normalized = evidence.map { normalizedText($0.text) }
        let topics = supportedTopics(in: normalized)
        let topic = topics.isEmpty ? "Unresolved topic; episode context only" : topics.joined(separator: " and ")
        let episode = compact(source.title, limit: 80)
        let title = topics.isEmpty ? "\(episode) — Clip \(clip.id)" : sentenceCase(topic)
        let context = "From \(episode), clip \(clip.id)."

        let firstWord = tokens(opening.text).first ?? ""
        let continuation = ["and", "but", "so", "he", "she", "they", "it", "that", "this", "because"].contains(firstWord)
        let openingQuestion = opening.text.contains("?") || ["why", "how", "what", "when", "where", "who"].contains(firstWord)
        let narrativeCues = ["i remember", "when i", "i learned", "i felt", "we were", "my family", "my experience"]
        let narrativeSegments = normalized.filter { text in narrativeCues.contains { contains($0, in: text) } }.count
        let discussion = normalized.contains { text in
            ["i disagree", "we disagree", "on the other hand", "however"].contains { contains($0, in: text) }
        }
        let reasoning = normalized.contains { contains("because", in: $0) }
        let openingAligned = abs(opening.start - clip.intervals[0].start) < 0.001
        let natural = clip.intervals.allSatisfy { interval in
            let starts = transcript.segments.contains { abs($0.start - interval.start) < 0.001 }
            let ends = transcript.segments.contains { abs($0.end - interval.end) < 0.001 && sentenceEnds($0.text) }
            return starts && ends
        }
        let supportedDuration = evidence.reduce(0.0) { $0 + $1.end - $1.start }
        let supportFraction = min(1, supportedDuration / clip.expectedDuration)
        let repeatedTopic = topics.contains { candidate in normalized.filter { contains(candidate, in: $0) }.count >= 2 }

        // Each factor is 0...10. Weights reflect the requested platform emphasis, not fitted
        // engagement statistics. Unknown audience fit and timeliness deliberately receive little credit.
        let hook = openingAligned ? (openingQuestion ? 7 : narrativeSegments > 0 ? 6 : 3) : 2
        let comprehension = openingAligned && !continuation ? (topics.isEmpty ? 4 : 7) : 2
        let standalone = !continuation && openingAligned && natural && !topics.isEmpty ? 7 : 3
        let relevance = repeatedTopic ? 7 : topics.isEmpty ? 2 : 4
        let debate = discussion ? (reasoning ? 9 : 6) : reasoning ? 4 : 1
        let narrative = narrativeSegments >= 2 ? 8 : narrativeSegments == 1 ? 5 : 1
        let shareability = min(comprehension, standalone) + (narrativeSegments > 0 ? 1 : 0)
        let attention = evidence.count >= 3 && supportFraction >= 0.7 ? 6 : 3
        let boundaries = natural ? 8 : 2
        let accuracy = qa.limitations.isEmpty && supportFraction >= 0.7 ? 7 : 4
        let factors = [hook, comprehension, standalone, relevance, debate, narrative,
                       shareability, 2, 2, attention, boundaries, accuracy]
        let xWeights = [10, 8, 12, 10, 18, 5, 8, 6, 10, 4, 4, 5]
        let instagramWeights = [16, 14, 12, 5, 4, 14, 10, 5, 3, 8, 5, 4]

        let rationale = [
            "Opening hook: \(openingQuestion ? "question wording is present" : narrativeSegments > 0 ? "first-person narrative wording is present" : "no strong opening cue was detected"); lexical evidence alone does not establish an engaging hook.",
            "Immediate comprehensibility: \(openingAligned && !continuation ? "opening aligns with a transcript segment without a detected continuation word" : "the cut or opening wording may depend on earlier context"); listener comprehension is unverified.",
            "Standalone context: \(standalone == 7 ? "topic cues and aligned endpoints support a self-contained excerpt" : "available wording or boundaries leave context uncertain"); speaker identities and external references are unverified.",
            "Topic relevance: \(topics.isEmpty ? "no supported topic in the conservative fallback vocabulary" : "transcript-supported topic: " + topic); intended-audience relevance is unknown.",
            "Meaningful disagreement: \(discussion ? "contrast wording is present" : reasoning ? "reason-giving wording is present without an explicit disagreement cue" : "no explicit discussion cue detected"); substance and speaker agreement cannot be proven by keywords.",
            "Emotional or narrative interest: \(narrativeSegments) segment(s) contain personal-narrative cues; emotion, sincerity and story quality are not inferred.",
            "Shareability: based on the same context and comprehensibility evidence; no observed sharing or engagement data is available.",
            "Audience relevance: unverified; no audience analytics or account-specific preferences are supplied to this fallback.",
            "Timeliness: unverified; transcript references such as today do not establish current relevance or event accuracy.",
            "Sustained attention: \(evidence.count) fully contained segment(s) span \(Int((supportFraction * 100).rounded()))% of retained time; this measures textual support, not viewer retention or transcript completeness.",
            "Natural boundaries: \(natural ? "all source intervals align with transcript starts and punctuated endings" : "one or more cuts lack aligned, punctuated transcript endpoints"); punctuation is not proof of a complete discussion.",
            "Editorial accuracy: source and accepted-QA identities match; only wholly retained transcript text supplies content. Transcript errors, omitted speech and factual claims remain unverified."
        ]
        var notes = ["Future-production advisory only. No accepted filename, interval or media is changed. Any later adjustment must preserve exact chronological coverage and verified shared duration limits."]
        for interval in clip.intervals {
            if let crossing = transcript.segments.first(where: { $0.start < interval.start && $0.end > interval.start }) {
                notes.append("Start \(seconds(interval.start))s crosses transcript segment \(seconds(crossing.start))–\(seconds(crossing.end))s. A future plan can examine the full sentence for missing context; no expansion is authorized here.")
            }
            if let crossing = transcript.segments.first(where: { $0.start < interval.end && $0.end > interval.end }) {
                notes.append("End \(seconds(interval.end))s crosses transcript segment \(seconds(crossing.start))–\(seconds(crossing.end))s. A future plan can examine the next natural endpoint without omitting or repeating speech.")
            }
        }
        if natural { notes.append("Current cuts align with transcript segment starts and punctuated endings; no boundary adjustment suggested by this fallback.") }
        if !natural && notes.count == 1 { notes.append("Current cuts have unmatched or unpunctuated transcript endpoints. Future planning should check surrounding sentences before changing any boundary.") }

        return ClipRecommendation(
            title: title, topic: topic,
            xCaption: "\(title). \(context) What stands out in this discussion?",
            instagramCaption: "\(title).\n\(context)",
            xScore: score(factors, weights: xWeights), instagramScore: score(factors, weights: instagramWeights),
            rationale: rationale,
            confidence: "Low — deterministic transcript-only fallback; audience fit, timeliness, speaker context and semantic accuracy are unverified.",
            boundaryNotes: notes,
            restrictions: [
                "This is a deterministic lexical fallback, not model-assisted editorial analysis.",
                "Scores are explainable editorial heuristics, not probabilities of virality or performance forecasts.",
                "Titles describe supported topics only; they do not assert quotes, speaker attribution, allegations or factual agreement.",
                "Timestamp validation binds the transcript to the source but does not prove complete speech coverage or transcription accuracy.",
                "Accepted clips and full-source production coverage remain unchanged regardless of score.",
                "Recommendation does not establish current account capabilities, Buffer readiness, rights, publication or platform ingestion."
            ] + qa.limitations.map { "Existing QA limitation: " + $0 },
            transcriptEvidence: evidence)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    private static func normalizedText(_ text: String) -> String { " " + tokens(text).joined(separator: " ") + " " }
    private static func contains(_ phrase: String, in text: String) -> Bool { text.contains(" " + phrase + " ") }
    private static func sentenceEnds(_ text: String) -> Bool { ".!?".contains(text.trimmingCharacters(in: .whitespacesAndNewlines).last ?? " ") }
    private static func compact(_ text: String, limit: Int) -> String {
        let result = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result.count <= limit ? result : String(result.prefix(limit - 1)) + "…"
    }
    private static func sentenceCase(_ text: String) -> String { String(text.prefix(1)).uppercased() + text.dropFirst() }
    private static func seconds(_ value: Double) -> String { String(value) }
    private static func score(_ factors: [Int], weights: [Int]) -> Int {
        min(100, max(0, Int((Double(zip(factors, weights).reduce(0) { $0 + $1.0 * $1.1 }) / 10).rounded())))
    }

    private static func supportedTopics(in segments: [String]) -> [String] {
        // An intentionally conservative vocabulary avoids turning random fragments, profanity,
        // proper names or allegations into asserted headlines. Unknown subjects use episode context.
        let vocabulary = ["music contracts", "creative control", "record labels", "mental health", "social media",
                          "music industry", "criminal justice", "music", "contracts", "ownership", "touring",
                          "business", "friendship", "family", "parenting", "education", "basketball", "football",
                          "comedy", "podcasting", "relationships", "health", "career", "money", "community",
                          "housing", "technology", "voting", "elections", "sports", "independence"]
        let candidates = vocabulary.compactMap { phrase -> (String, Int)? in
            let count = segments.filter { contains(phrase, in: $0) }.count
            return count > 0 ? (phrase, count) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let left = $0.0.split(separator: " ").count, right = $1.0.split(separator: " ").count
            if left != right { return left > right }
            return $0.0 < $1.0
        }
        var selected: [String] = []
        for (phrase, _) in candidates {
            guard !selected.contains(where: { contains(phrase, in: " " + $0 + " ") || contains($0, in: " " + phrase + " ") }) else { continue }
            selected.append(phrase)
            if selected.count == 2 { break }
        }
        return selected
    }
}
