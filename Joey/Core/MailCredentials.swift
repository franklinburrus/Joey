import Foundation
import Security
import LocalAuthentication

public struct MailSecret: Codable, Sendable {
    public var password: String
    public var token: String
    public init(password: String, token: String) {self.password = password;self.token = token}
}

/// Only Joey's own non-synchronizing generic-password item is accessible here.
/// Apple Mail credentials and other applications' items are never queried.
public enum MailCredentials {
    private static let service = "com.joey.icloud-intake"
    private static func query(_ account: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
         kSecAttrAccount as String:account, kSecAttrSynchronizable as String:false]
    }
    public static func read(account: String) throws -> MailSecret? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext();context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecItemNotFound {return nil}
        guard status == errSecSuccess, let data = result as? Data else {throw failure(status)}
        do {return try JSONDecoder().decode(MailSecret.self,from:data)}
        catch {throw JoeyError.dependency("Joey's iCloud Keychain item is unreadable; save the app-specific password again")}
    }
    public static func save(_ secret: MailSecret, account: String) throws {
        guard !secret.password.isEmpty, secret.password.utf8.count <= 512, secret.token.utf8.count == 43 else {
            throw JoeyError.invalid("App-specific password or generated intake token is invalid")
        }
        let data = try JSONEncoder().encode(secret)
        let status = SecItemUpdate(query(account) as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary,nil)
            guard added == errSecSuccess else {throw failure(added)}
        } else if status != errSecSuccess {throw failure(status)}
        guard let stored = try read(account:account), stored.password == secret.password, stored.token == secret.token else {
            throw JoeyError.failed("Joey's iCloud credential could not be read back from Keychain")
        }
    }
    public static func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {throw failure(status)}
        guard try read(account:account) == nil else {throw JoeyError.failed("Joey's iCloud credential is still present")}
    }
    public static func generateToken() throws -> String {
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else {
            throw JoeyError.failed("Secure intake-token generation failed")
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of:"+",with:"-")
            .replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    private static func failure(_ status: OSStatus) -> JoeyError {
        .dependency("Joey iCloud Keychain access failed (\(status)). Unlock the login Keychain and save the app-specific password in this app build.")
    }
}

public struct MailCheckFailure: Error, LocalizedError, Sendable {
    public let code: String
    public init(_ code: String) {self.code = code}
    public var errorDescription: String? {Self.message(code)}
    public static func message(_ code: String) -> String {
        switch code {
        case "authenticationFailed": return "iCloud rejected the app-specific password. Automatic login retries stopped; save a valid app password and test again."
        case "credentialUnavailable": return "Save Joey's iCloud app-specific password in native setup. No saved credential is available to this build."
        case "uidValidityChanged": return "INBOX identifiers changed. Receipts and jobs are retained. Review the queue, then establish a fresh baseline; older mailbox contents will not replay."
        case "networkUnavailable": return "iCloud could not be reached within the deadline. Pending work is retained; checks will retry."
        case "mailboxUnavailable": return "The primary iCloud account's INBOX could not be opened read-only. Verify the primary Mail login."
        case "intakeTokenMissingOrInvalid": return "Authorization pending: resend using the saved Joey template with its current token."
        case "senderAuthenticationUnavailable": return "Sender authentication is unavailable. Configure the secret intake token before automatic processing."
        case "senderNotAllowed": return "Sender is not in the allowed-address list."
        case "tooManyLinks": return "Message exceeds the 10 distinct source-link limit. Send smaller messages."
        case "messageTooLarge", "headersTooLarge": return "Message exceeds Joey's bounded size limit. Send only the source links and token."
        case "noSupportedLinks": return "No supported original HTTPS YouTube/X source link was found."
        case "templateToken": return "Allowed sender and secret template token verified."
        case "dismissed": return "Authorization-pending receipt dismissed locally; server mail retained."
        default: return "Email intake could not accept this result (\(code)). Pending work and server mail are retained."
        }
    }
}

public enum ICloudMail {
    public static func check(action: String, settings: EmailIntakeSettings, secret: MailSecret,
                             baseline: EmailBaseline?, capacity: Int, root: URL) async throws -> EmailScan {
        // Checking mail must not discover models or run the ASR setup path.
        let configURL = root.appendingPathComponent("settings.json")
        let config: Configuration? = FileManager.default.fileExists(atPath:configURL.path) ? try Persistence.load(configURL):nil
        // Mail secrets travel on stdin only to an owned virtualenv Python.
        let python = try Processes.credentialPython(config?.pythonPath)
        #if SWIFT_PACKAGE
        let script = Bundle.module.url(forResource:"mail_intake",withExtension:"py")
        #else
        let script = Bundle.main.url(forResource:"mail_intake",withExtension:"py")
        #endif
        guard let script else {throw JoeyError.dependency("Bundled iCloud helper is missing from this build")}
        var input: [String:Any] = ["action":action,"account":settings.account,"password":secret.password,
                                  "token":secret.token,"allowedSenders":settings.allowedSenders,"capacity":capacity]
        if let baseline {input["uidValidity"] = baseline.uidValidity;input["frontier"] = baseline.frontier}
        let bytes = try JSONSerialization.data(withJSONObject:input)
        let result: ProcessResult
        do {result = try await Processes.run(python,[script.path],maxOutput:512*1024,input:bytes,timeout:60)}
        catch is CancellationError {throw CancellationError()}
        catch {throw MailCheckFailure("networkUnavailable")}
        if let object = try JSONSerialization.jsonObject(with:result.stdout) as? [String:Any], let code = object["error"] as? String {
            let safeCodes = ["authenticationFailed","uidValidityChanged","networkUnavailable","invalidInput","mailboxUnavailable","invalidMailboxResponse"]
            throw MailCheckFailure(safeCodes.contains(code) ? code:"invalidMailboxResponse")
        }
        do {
            let scan = try JSONDecoder().decode(EmailScan.self,from:result.stdout)
            try scan.validate();return scan
        } catch {throw MailCheckFailure("invalidMailboxResponse")}
    }
}
