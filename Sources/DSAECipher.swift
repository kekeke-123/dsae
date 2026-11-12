import Foundation
import CryptoKit
import CommonCrypto

enum DSAEError: LocalizedError {
    case emptyPassword
    case emptyInput
    case passwordMismatch
    case badFormat
    case wrongPassword
    case keyDerivationFailed
    case sealFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "请先输入口令。"
        case .emptyInput:
            return "没有可以处理的内容。"
        case .passwordMismatch:
            return "两次输入的口令不一致。"
        case .badFormat:
            return "数据格式不正确，或内容已被改动。"
        case .wrongPassword:
            return "口令错误，或数据已损坏。"
        case .keyDerivationFailed:
            return "密钥派生失败，请重试。"
        case .sealFailed:
            return "编码失败，请重试。"
        case .tooLarge:
            return "文件超过 200 MB 上限，请先拆分后再处理。"
        }
    }
}

/// DSAE 核心：口令 → PBKDF2-HMAC-SHA256 派生 256 位密钥 → AES-256-GCM 认证加密。
/// 所有运算在本机完成，不产生任何网络请求。
enum DSAECipher {

    /// 文件头魔数 "DSAE1"
    static let magic: [UInt8] = [0x44, 0x53, 0x41, 0x45, 0x31]
    static let saltLength = 16
    static let keyLength = 32
    static let tagLength = 16
    static let iterations: UInt32 = 120_000
    static let textPrefix = "DSAE1-"
    static let fileExtension = "dsae"
    static let maxFileBytes = 200 * 1024 * 1024

    static func deriveKey(password: String, salt: [UInt8]) -> SymmetricKey? {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = derived.withUnsafeMutableBufferPointer { derivedBuf -> Int32 in
            salt.withUnsafeBufferPointer { saltBuf -> Int32 in
                password.withCString { passPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr,
                        password.utf8.count,
                        saltBuf.baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBuf.baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derived))
    }

    static func makeSalt() -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<saltLength).map { _ in UInt8.random(in: 0...255, using: &generator) }
    }

    /// 输出结构：magic(5) + salt(16) + AES-GCM combined(nonce + 密文 + tag)
    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw DSAEError.emptyPassword }
        guard !plaintext.isEmpty else { throw DSAEError.emptyInput }

        let salt = makeSalt()
        guard let key = deriveKey(password: password, salt: salt) else {
            throw DSAEError.keyDerivationFailed
        }

        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw DSAEError.sealFailed }
            var payload = Data(magic)
            payload.append(contentsOf: salt)
            payload.append(combined)
            return payload
        } catch is DSAEError {
            throw DSAEError.sealFailed
        } catch {
            throw DSAEError.sealFailed
        }
    }

    static func decrypt(_ payload: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw DSAEError.emptyPassword }
        guard payload.count > magic.count + saltLength + tagLength else {
            throw DSAEError.badFormat
        }

        let bytes = [UInt8](payload)
        guard Array(bytes[0..<magic.count]) == magic else { throw DSAEError.badFormat }

        let salt = Array(bytes[magic.count..<(magic.count + saltLength)])
        let body = payload.subdata(in: (magic.count + saltLength)..<payload.count)

        guard let key = deriveKey(password: password, salt: salt) else {
            throw DSAEError.keyDerivationFailed
        }

        do {
            let box = try AES.GCM.SealedBox(combined: body)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw DSAEError.wrongPassword
        }
    }

    // MARK: - 文本

    static func encryptText(_ text: String, password: String) throws -> String {
        let payload = try encrypt(Data(text.utf8), password: password)
        return textPrefix + payload.base64EncodedString()
    }

    static func decryptText(_ text: String, password: String) throws -> String {
        var base64 = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !base64.isEmpty else { throw DSAEError.emptyInput }
        if base64.hasPrefix(textPrefix) {
            base64.removeFirst(textPrefix.count)
        }
        guard let payload = Data(base64Encoded: base64) else { throw DSAEError.badFormat }
        let plain = try decrypt(payload, password: password)
        guard let string = String(data: plain, encoding: .utf8) else { throw DSAEError.badFormat }
        return string
    }

    // MARK: - 文件

    static func encryptFile(at url: URL, password: String) throws -> URL {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maxFileBytes {
            throw DSAEError.tooLarge
        }
        let plaintext = try Data(contentsOf: url)
        guard plaintext.count <= maxFileBytes else { throw DSAEError.tooLarge }
        guard !plaintext.isEmpty else { throw DSAEError.emptyInput }

        let payload = try encrypt(plaintext, password: password)
        let baseName = url.deletingPathExtension().lastPathComponent
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName + "-" + timestamp() + "." + fileExtension)
        try payload.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func decryptFile(at url: URL, password: String) throws -> URL {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maxFileBytes + 4096 {
            throw DSAEError.tooLarge
        }
        let payload = try Data(contentsOf: url)
        let plaintext = try decrypt(payload, password: password)
        guard !plaintext.isEmpty else { throw DSAEError.emptyInput }

        let rawName = url.lastPathComponent
        let name: String
        if rawName.lowercased().hasSuffix("." + fileExtension) {
            name = String(rawName.dropLast(fileExtension.count + 1))
        } else {
            name = "DSAE-还原-" + timestamp() + ".bin"
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try plaintext.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    static func humanSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
