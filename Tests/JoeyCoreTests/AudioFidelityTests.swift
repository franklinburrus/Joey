import XCTest
@testable import JoeyCore

final class AudioFidelityTests: XCTestCase {
    private let rate = 12_000

    private func tone(_ frequency: Double = 440, amplitude: Double = 0.2, count: Int = 12_000) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / 12_000)) }
    }

    private func stereo(_ left: [Float], _ right: [Float]) -> [Float] {
        zip(left, right).flatMap { [$0.0, $0.1] }
    }

    func testIndependentQuietSignalsPassAbsoluteErrorBudgetWithoutClaimingCorrelation() throws {
        let source = (0..<rate).map { Float($0.isMultiple(of: 2) ? 0.00012 : -0.00012) }
        let output = (0..<rate).map { Float($0 % 4 < 2 ? 0.00018 : -0.00018) }
        // Orthogonal source/output signals have zero correlation and gain 1.5.
        // Both energies and their actual zero-lag difference remain below the
        // inherited one-second quiet budget of 0.001.
        let report = try Media.validateAudioSamples(source, output, channels: 1, duration: 1)
        XCTAssertTrue(report.contains("0 relative-fidelity channel windows"), report)
        XCTAssertTrue(report.contains("1 quiet channel windows"), report)
        XCTAssertTrue(report.contains("zero-lag error"), report)
        XCTAssertFalse(report.contains("minimum zero-lag correlation"), report)
    }

    func testQuietInversionExceedingAbsoluteErrorBudgetStillFails() {
        let source = (0..<rate).map { Float($0.isMultiple(of: 2) ? 0.0002 : -0.0002) }
        // Each signal has energy 0.00048, but their difference has 0.00192.
        XCTAssertThrowsError(try Media.validateAudioSamples(source, source.map { -$0 }, channels: 1, duration: 1)) {
            XCTAssertTrue($0.localizedDescription.contains("Audio fidelity/sync failed"), $0.localizedDescription)
        }
    }

    func testZeroSourceRejectsOutputAboveQuietBudgetWithActionableError() throws {
        let source = [Float](repeating: 0, count: rate)
        XCTAssertNoThrow(try Media.validateAudioSamples(source, [Float](repeating: 0.0002, count: rate), channels: 1, duration: 1))
        XCTAssertThrowsError(try Media.validateAudioSamples(source, [Float](repeating: 0.0003, count: rate), channels: 1, duration: 1)) {
            XCTAssertTrue($0.localizedDescription.contains("Source silence"), $0.localizedDescription)
        }
    }

    func testAboveBudgetDamageStillRequiresOriginalCorrelationAndGainBounds() throws {
        let source = tone()
        let unchanged = try Media.validateAudioSamples(source, source, channels: 1, duration: 1)
        XCTAssertTrue(unchanged.contains("1 relative-fidelity channel windows"), unchanged)
        XCTAssertTrue(unchanged.contains("minimum zero-lag correlation"), unchanged)
        XCTAssertTrue(unchanged.contains("0 quiet channel windows"), unchanged)
        XCTAssertNoThrow(try Media.validateAudioSamples(source, source.map { $0 * 0.71 }, channels: 1, duration: 1))
        XCTAssertNoThrow(try Media.validateAudioSamples(source, source.map { $0 * 1.39 }, channels: 1, duration: 1))
        let shifted = Array(source.suffix(100)) + Array(source.dropLast(100))
        let cases: [(String, [Float])] = [
            ("mute", [Float](repeating: 0, count: rate)),
            ("shift", shifted),
            ("substitution", tone(997)),
            ("inversion", source.map { -$0 }),
            ("low gain", source.map { $0 * 0.69 }),
            ("high gain", source.map { $0 * 1.41 })
        ]
        for (name, output) in cases {
            XCTAssertThrowsError(try Media.validateAudioSamples(source, output, channels: 1, duration: 1), name) {
                XCTAssertTrue($0.localizedDescription.contains("Audio fidelity/sync failed"), "\(name): \($0)")
            }
        }
    }

    func testOneBadStereoChannelCannotBeHiddenByTheOtherChannel() throws {
        let signal = tone(), silence = [Float](repeating: 0, count: rate)
        let source = stereo(signal, signal)
        XCTAssertThrowsError(try Media.validateAudioSamples(source, stereo(signal, signal.map { -$0 }), channels: 2, duration: 1))
        let quietSource = stereo(signal, silence)
        XCTAssertThrowsError(try Media.validateAudioSamples(quietSource,
            stereo(signal, [Float](repeating: 0.0003, count: rate)), channels: 2, duration: 1))
    }

    func testFractionalFinalWindowUsesItsActualPerChannelSampleCount() throws {
        for channels in [1, 2] {
            let source = [Float](repeating: 0, count: 15_000 * channels)
            var insideBudget = source, outsideBudget = source
            for index in (rate * channels)..<source.count {
                insideBudget[index] = 0.0002
                outsideBudget[index] = 0.0003
            }
            // The final quarter-second permits energy below 0.00025 per
            // channel, preserving the same RMS limit as a full second.
            XCTAssertNoThrow(try Media.validateAudioSamples(source, insideBudget, channels: channels, duration: 1.25))
            XCTAssertThrowsError(try Media.validateAudioSamples(source, outsideBudget, channels: channels, duration: 1.25),
                "A fractional quiet window must not inherit a full second's energy allowance")
        }
    }

    func testFractionalWindowAlsoScalesTheAbsoluteDifferenceBudget() {
        let source = [Float](repeating: 0.0002, count: 3_000)
        // Both individual energies fit the quarter-second budget (0.00012),
        // but inversion produces difference energy 0.00048, exceeding 0.00025.
        XCTAssertThrowsError(try Media.validateAudioSamples(source, source.map { -$0 }, channels: 1, duration: 0.25))
    }

    func testPlannedDurationPaddingAndDurationMismatchChecksRemainIntact() throws {
        let source = tone(count: rate + 8)
        var output = source
        for index in rate..<output.count { output[index] = -source[index] }
        XCTAssertNoThrow(try Media.validateAudioSamples(source, output, channels: 1, duration: 1))
        XCTAssertThrowsError(try Media.validateAudioSamples(source, output, channels: 1, duration: 1 + 8.0 / 12_000))
        XCTAssertThrowsError(try Media.validateAudioSamples(source, Array(source.dropLast(901)), channels: 1, duration: 1)) {
            XCTAssertTrue($0.localizedDescription.contains("75ms encoding tolerance"), $0.localizedDescription)
        }
    }

    func testShortWindowsRetainSourceSilenceQuietAudioAndEndpointAllowance() throws {
        var source = tone(count: rate * 2)
        for index in 4_800..<6_000 { source[index] = 0 }
        for index in 12_000..<15_000 { source[index] *= 0.0001 }
        XCTAssertNoThrow(try Media.validateAudioSamples(source, source, channels: 1, duration: 2))
        XCTAssertNoThrow(try Media.validateAudioSamples(source, Array(source.dropLast(900)), channels: 1, duration: 2))
    }

    func testShortDropoutAtFractionalWindowPositionFailsInEitherChannel() {
        let signal = tone(count: rate * 2)
        var damaged = signal
        for index in 5_136..<6_336 { damaged[index] = 0 }
        XCTAssertThrowsError(try Media.validateAudioSamples(signal, damaged, channels: 1, duration: 2)) {
            XCTAssertTrue($0.localizedDescription.contains("short-window"), $0.localizedDescription)
        }
        for output in [stereo(signal, damaged), stereo(damaged, signal)] {
            XCTAssertThrowsError(try Media.validateAudioSamples(stereo(signal, signal), output, channels: 2, duration: 2))
        }
    }
}
