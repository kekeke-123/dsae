import Foundation
import Security

/// 优先存钥匙串；在未签名安装、钥匙串不可用时落到 App 沙盒文件里。
enum SecretStore {

    static func set(_ value: String, _ account: String) {
        if Keychain.set(value, for: account) {
            // 钥匙串写入成功时，清掉可能存在的旧降级文件，避免读到过期值。
            try? FileManager.default.removeItem(at: fileURL(account))
            return
        }
        writeFile(value, account)
    }

    static func get(_ account: String) -> String? {
        if let value = Keychain.get(account) { return value }
        return readFile(account)
    }

    static func delete(_ account: String) {
        Keychain.delete(account)
        try? FileManager.default.removeItem(at: fileURL(account))
    }

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("DSAE", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(_ account: String) -> URL {
        let safe = account.replacingOccurrences(of: "/", with: "_")
        return directory()?.appendingPathComponent(safe + ".dat") ?? URL(fileURLWithPath: "/tmp/dsae-" + safe)
    }

    private static func writeFile(_ value: String, _ account: String) {
        guard let data = value.data(using: .utf8) else { return }
        try? data.write(to: fileURL(account), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func readFile(_ account: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(account)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum Keychain {

    private static let service = "com.dsae.encryptor"

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        delete(account)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
