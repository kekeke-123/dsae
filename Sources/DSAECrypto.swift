import Foundation
import CryptoKit
import CommonCrypto

enum DSAEError: LocalizedError {
    case emptyPassword
    case emptyInput
    case badFormat
    case wrongPassword
    case notDecryptable
    case noDigest
    case keyDerivationFailed
    case sealFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "口令为空。"
        case .emptyInput:
            return "没有可处理的内容。"
        case .badFormat:
            return "这不是 DSAE 产物，或内容已损坏。"
        case .wrongPassword:
            return "当前口令打不开这份产物。"
        case .notDecryptable:
            return "随机加密的产物无法还原，只能用来验证文件是否一致。"
        case .noDigest:
            return "这份产物里没有验证指纹，无法校验。"
        case .keyDerivationFailed:
            return "密钥派生失败，请重试。"
        case .sealFailed:
            return "加密失败，请重试。"
        case .tooLarge:
            return "文件超过 200 MB 上限，请先拆分。"
        }
    }
}

enum DSAEMode: UInt8 {
    case password = 1
    case random = 2
}

/// 产物结构（二进制，不使用 Base64）
/// 0-3  魔数 "DSAE"
/// 4    版本 1
/// 5    模式 1=口令加密 2=随机加密
/// 6    原扩展名长度 n
/// 7..  n 字节原扩展名
/// next 1 字节盐长度 m
/// next m 字节盐
/// next 1 字节指纹长度 k
/// next k 字节 SHA-256(原文)
/// rest AES-GCM combined（nonce + 密文 + tag）
enum DSAECrypto {

    static let magic: [UInt8] = [0x44, 0x53, 0x41, 0x45]
    static let version: UInt8 = 1
    static let saltLength = 16
    static let keyLength = 32
    static let digestLength = 32
    static let iterations: UInt32 = 120_000
    static let maxBytes = 200 * 1024 * 1024

    // MARK: - 随机

    static func randomData(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - 密钥

    static func deriveKey(password: String, salt: Data) -> SymmetricKey? {
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = derived.withUnsafeMutableBufferPointer { derivedBuf -> Int32 in
            saltBytes.withUnsafeBufferPointer { saltBuf -> Int32 in
                password.withCString { passPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr,
                        password.utf8.count,
                        saltBuf.baseAddress,
                        saltBytes.count,
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

    // MARK: - 打包

    static func seal(plain: Data, password: String, ext: String) throws -> Data {
        guard !password.isEmpty else { throw DSAEError.emptyPassword }
        guard !plain.isEmpty else { throw DSAEError.emptyInput }
        let salt = randomData(saltLength)
        guard let key = deriveKey(password: password, salt: salt) else {
            throw DSAEError.keyDerivationFailed
        }
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            throw DSAEError.sealFailed
        }
        return pack(mode: .password, ext: ext, salt: salt, digest: nil, body: combined)
    }

    static func sealRandom(plain: Data, ext: String) throws -> Data {
        guard !plain.isEmpty else { throw DSAEError.emptyInput }
        let salt = randomData(saltLength)
        // 随机密钥用完立即丢弃，所以这份产物不可还原。
        let key = SymmetricKey(size: .bits256)
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            throw DSAEError.sealFailed
        }
        return pack(mode: .random, ext: ext, salt: salt, digest: sha256(plain), body: combined)
    }

    private static func pack(mode: DSAEMode, ext: String, salt: Data, digest: Data?, body: Data) -> Data {
        var payload = Data(magic)
        payload.append(version)
        payload.append(mode.rawValue)

        let extData = Data(ext.utf8.prefix(40))
        payload.append(UInt8(extData.count))
        payload.append(extData)

        payload.append(UInt8(salt.count))
        payload.append(salt)

        if let digest {
            payload.append(UInt8(digest.count))
            payload.append(digest)
        } else {
            payload.append(0)
        }

        payload.append(body)
        return payload
    }

    // MARK: - 解析

    struct Envelope {
        let mode: DSAEMode
        let ext: String
        let salt: Data
        let digest: Data?
        let body: Data
    }

    static func parse(_ payload: Data) throws -> Envelope {
        let bytes = [UInt8](payload)
        var index = 0

        func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, index + count <= bytes.count else { throw DSAEError.badFormat }
            let slice = Array(bytes[index..<(index + count)])
            index += count
            return slice
        }

        let magicBytes = try take(magic.count)
        guard magicBytes == magic else { throw DSAEError.badFormat }

        let versionByte = try take(1)
        guard versionByte.first == version else { throw DSAEError.badFormat }

        let modeByte = try take(1)
        guard let mode = DSAEMode(rawValue: modeByte.first ?? 0) else { throw DSAEError.badFormat }

        let extLen = Int(try take(1).first ?? 0)
        let extBytes = try take(extLen)

        let saltLen = Int(try take(1).first ?? 0)
        let saltBytes = try take(saltLen)

        let digestLen = Int(try take(1).first ?? 0)
        let digestBytes = try take(digestLen)

        let body = Data(bytes[index...])

        return Envelope(
            mode: mode,
            ext: String(decoding: extBytes, as: UTF8.self),
            salt: Data(saltBytes),
            digest: digestLen == 0 ? nil : Data(digestBytes),
            body: body
        )
    }

    // MARK: - 还原

    static func open(_ payload: Data, candidates: [String]) throws -> (data: Data, ext: String) {
        let envelope = try parse(payload)
        guard envelope.mode == .password else { throw DSAEError.notDecryptable }

        for candidate in candidates where !candidate.isEmpty {
            guard let key = deriveKey(password: candidate, salt: envelope.salt) else {
                throw DSAEError.keyDerivationFailed
            }
            if let box = try? AES.GCM.SealedBox(combined: envelope.body),
               let plain = try? AES.GCM.open(box, using: key) {
                return (plain, envelope.ext)
            }
        }
        throw DSAEError.wrongPassword
    }

    // MARK: - 验证

    static func matches(_ payload: Data, candidate: Data) throws -> Bool {
        let envelope = try parse(payload)
        guard let digest = envelope.digest else { throw DSAEError.noDigest }
        return sha256(candidate) == digest
    }

    // MARK: - 十六进制（代替 Base64）

    static func hexEncode(_ data: Data) -> String {
        var output = ""
        output.reserveCapacity(data.count * 2)
        for byte in data {
            output += String(format: "%02x", byte)
        }
        return output
    }

    static func hexDecode(_ text: String) -> Data? {
        let cleaned = text.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let value = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        return Data(bytes)
    }

    // MARK: - 命名

    /// file.txt → file.dsaetxt ；file → file.dsae
    static func sealedName(for name: String) -> String {
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let base = nsName.deletingPathExtension
        if ext.isEmpty { return base + ".dsae" }
        return base + ".dsae" + ext
    }

    /// file.dsaetxt → file.txt
    static func restoredName(fromSealed name: String) -> String? {
        guard let range = name.range(of: ".dsae", options: .backwards) else { return nil }
        let base = String(name[name.startIndex..<range.lowerBound])
        let tail = String(name[range.upperBound..<name.endIndex])
        guard !base.isEmpty else { return nil }
        if tail.isEmpty { return base }
        return base + "." + tail
    }
}
