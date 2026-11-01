import Foundation

public struct JoeBranding: Codable, Sendable {
    public static let logoID = "1rOBwiIFLGvglfDye1hlMh2HrL1PqRdfl"
    public static let outroID = "1aIEOk1KUaYu82rL98Hfx1gufCM4cy6bw"
    public static let logoSHA256 = "840a069f09611f1943722c0aa503891c129ad390f9aa88417f8e9a1ddafff013"
    public static let outroSHA256 = "1ed728d94a14573fd93c3358440269418d5488fcb14abbc96faf78ace7d5b0a4"
    public var logo: EvidenceFile
    public var outro: EvidenceFile
    public var outroDuration: Double {7.3}
    public static func load(root: URL) throws -> JoeBranding {
        let result = JoeBranding(
            logo:EvidenceFile(path:root.appendingPathComponent("assets/joe-dub-logo.png").path,sha256:logoSHA256,basis:"Frank-approved DUB Primary Logo; Drive "+logoID),
            outro:EvidenceFile(path:root.appendingPathComponent("assets/joe-approved-outro.mov").path,sha256:outroSHA256,basis:"Frank-approved full outro; Drive "+outroID))
        try result.validate();return result
    }
    public func validate() throws {
        guard logo.sha256 == Self.logoSHA256, outro.sha256 == Self.outroSHA256 else {throw JoeyError.invalid("Joe branding must use the exact approved logo and outro")}
        try logo.validate();try outro.validate()
    }
}
