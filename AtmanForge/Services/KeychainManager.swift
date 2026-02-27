import Foundation
import CryptoKit

/// Stores secrets in Application Support using AES-GCM encryption with a
/// device-stable key. Works without code signing or keychain entitlements.
enum KeychainManager {
    private static let bundleID = "com.turbolynx.AtmanForge"

    private static var storageDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(bundleID)
    }

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let dir = storageDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encrypted = try encrypt(data)
        try encrypted.write(to: dir.appendingPathComponent(key))
    }

    static func load(key: String) -> String? {
        let url = storageDir.appendingPathComponent(key)
        guard let encrypted = try? Data(contentsOf: url),
              let decrypted = try? decrypt(encrypted) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    static func delete(key: String) {
        let url = storageDir.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Encryption

    private static var encryptionKey: SymmetricKey {
        // Derive a stable key from hardware UUID + bundle ID
        let seed = (hardwareUUID() + bundleID).data(using: .utf8)!
        let hash = SHA256.hash(data: seed)
        return SymmetricKey(data: hash)
    }

    private static func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: encryptionKey)
        guard let combined = sealed.combined else {
            throw CryptoKitError.underlyingCoreCryptoError(error: -1)
        }
        return combined
    }

    private static func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: encryptionKey)
    }

    private static func hardwareUUID() -> String {
        #if os(macOS)
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        if let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuid
        }
        return "fallback-uuid"
        #else
        return UIDevice.current.identifierForVendor?.uuidString ?? "fallback-uuid"
        #endif
    }
}
