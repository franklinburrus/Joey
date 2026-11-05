import Foundation

/// One duration contract for planning, encoder QA and delivery preflight.
/// Buffer's shared X/Instagram contract retains Joey's conservative five-second
/// minimum and 0.1-second measured ceiling margin. Planning additionally reserves
/// the existing 75 ms encoder tolerance, so passing plans can pass final QA.
public struct DurationPolicy: Sendable {
    public static let encodingTolerance = 0.075
    public static let bufferCeilingMargin = 0.1
    public let minimum: Double
    public let measuredMaximum: Double
    public let plannedMaximum: Double

    public init(profile: SharedProfile) {
        let buffer = !profile.isDriveOnly && [profile.x,profile.instagram].contains {
            $0?.surface.lowercased().contains("buffer") == true
        }
        minimum = buffer ? 5 : 0
        measuredMaximum = buffer ? min(140,profile.maxDuration) - Self.bufferCeilingMargin : profile.maxDuration
        plannedMaximum = profile.dubNativeMaster == true ? 600 : buffer ? measuredMaximum - Self.encodingTolerance : profile.maxDuration
    }

    public func validatePlanned(_ duration: Double) throws {
        guard duration.isFinite, duration > 0, duration >= minimum,
              duration <= plannedMaximum + Planning.tolerance else {
            throw JoeyError.invalid("Selected content duration \(duration)s conflicts with the shared duration policy: minimum \(minimum)s, planned maximum \(plannedMaximum)s. Exact selections and retained content were not altered.")
        }
    }

    public func validateMeasured(_ duration: Double, expected: Double) throws {
        guard duration.isFinite, expected.isFinite, duration > 0, duration >= minimum,
              duration <= measuredMaximum + Planning.tolerance,
              abs(duration-expected) <= Self.encodingTolerance + Planning.tolerance else {
            throw JoeyError.failed("Measured duration \(duration)s must satisfy \(minimum)–\(measuredMaximum)s and match \(expected)s source content within \(Self.encodingTolerance)s; accepted media preserved")
        }
    }
}
