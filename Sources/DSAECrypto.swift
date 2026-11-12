import Foundation
import CryptoKit
import CommonCrypto

enum DSAEError: LocalizedError {
    case emptyPassword
    case emptyInput
    case badFormat
    case damagedHeader
    case damagedBody
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
        case .damagedHeader:
            return "产物头部已损坏：结构被改动，或传输不完整。"
        case .damagedBody:
            return "产物数据部分已损坏：密文被改动。"
        case .wrongPassword:
            return "当前口令打不开这份产物。"
        case .notDecryptable:
            return "随机加密的产物无法还原，只能用来验证。"
        case .noDigest:
            return "这份产物里没有验证指纹。"
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

enum VerifyKind {
    case identical
    case tampered
    case damaged
}

struct VerifyResult {
    let kind: VerifyKind
    let detail: String
    let storedFingerprint: String
    let fileFingerprint: String
}

/// 产物结构（二进制，不使用 Base64）
///
/// 0-3   魔数 "DSAE"
/// 4     版本 2
/// 5     模式 1=口令加密 2=随机加密
/// 6     原扩展名长度 n
/// 7..   n 字节原扩展名
/// next  1 字节盐长度 m
/// next  m 字节盐
/// next  1 字节指纹长度 k
/// next  k 字节 SHA-256(原文)
/// next  8 字节头部校验 = SHA-256(以上所有头部字节) 的前 8 字节
/// next  8 字节数据校验 = SHA-256(密文) 的前 8 字节
/// rest  AES-GCM combined（nonce + 密文 + tag）
enum DSAECrypto {

    static let magic: [UInt8] = [0x44, 0x53, 0x41, 0x45]
    static let version: UInt8 = 2
    static let saltLength = 16
    static let keyLength = 32
    static let digestLength = 32
    static let checkLength = 8
    static let iterations: UInt32 = 120_000
    static let maxBytes = 200 * 1024 * 1024

    // MARK: - 基础

    static func randomData(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func humanSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

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
        guard plain.count <= maxBytes else { throw DSAEError.tooLarge }

        let salt = randomData(saltLength)
        guard let key = deriveKey(password: password, salt: salt) else {
            throw DSAEError.keyDerivationFailed
        }
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            throw DSAEError.sealFailed
        }
        return pack(mode: .password, ext: ext, salt: salt, digest: sha256(plain), body: combined)
    }

    static func sealRandom(plain: Data, ext: String) throws -> Data {
        guard !plain.isEmpty else { throw DSAEError.emptyInput }
        guard plain.count <= maxBytes else { throw DSAEError.tooLarge }

        let salt = randomData(saltLength)
        // 随机密钥用完立即丢弃，所以这份产物不可还原，只能用来验证。
        let key = SymmetricKey(size: .bits256)
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            throw DSAEError.sealFailed
        }
        return pack(mode: .random, ext: ext, salt: salt, digest: sha256(plain), body: combined)
    }

    private static func pack(mode: DSAEMode, ext: String, salt: Data, digest: Data?, body: Data) -> Data {
        var header = Data(magic)
        header.append(version)
        header.append(mode.rawValue)

        let extData = Data(ext.utf8.prefix(40))
        header.append(UInt8(extData.count))
        header.append(extData)

        header.append(UInt8(salt.count))
        header.append(salt)

        if let digest {
            header.append(UInt8(digest.count))
            header.append(digest)
        } else {
            header.append(0)
        }

        let headerCheck = Data(sha256(header).prefix(checkLength))
        let bodyCheck = Data(sha256(body).prefix(checkLength))

        var payload = header
        payload.append(headerCheck)
        payload.append(bodyCheck)
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
        guard saltLen == saltLength else { throw DSAEError.badFormat }

        let digestLen = Int(try take(1).first ?? 0)
        guard digestLen == 0 || digestLen == digestLength else { throw DSAEError.badFormat }
        let digestBytes = try take(digestLen)

        let headerEnd = index
        let headerCheck = try take(checkLength)
        let bodyCheck = try take(checkLength)

        let body = Data(bytes[index...])

        guard Array(sha256(Data(bytes[0..<headerEnd])).prefix(checkLength)) == headerCheck else {
            throw DSAEError.damagedHeader
        }
        guard Array(sha256(body).prefix(checkLength)) == bodyCheck else {
            throw DSAEError.damagedBody
        }

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

    // MARK: - 验证（不需要口令，可跨设备）

    static func verify(_ payload: Data, candidate: Data) -> VerifyResult {
        let fileFingerprint = shortFingerprint(candidate)

        let envelope: Envelope
        do {
            envelope = try parse(payload)
        } catch let error as DSAEError {
            switch error {
            case .damagedHeader:
                return VerifyResult(kind: .damaged,
                                    detail: "产物头部校验没通过：结构被改动，或文件没有完整传过来。",
                                    storedFingerprint: "—",
                                    fileFingerprint: fileFingerprint)
            case .damagedBody:
                return VerifyResult(kind: .damaged,
                                    detail: "产物数据部分校验没通过：密文被改动，这份产物本身已经损坏。",
                                    storedFingerprint: "—",
                                    fileFingerprint: fileFingerprint)
            default:
                return VerifyResult(kind: .damaged,
                                    detail: "这份文件不是完整的 DSAE 产物，无法比对。",
                                    storedFingerprint: "—",
                                    fileFingerprint: fileFingerprint)
            }
        } catch {
            return VerifyResult(kind: .damaged,
                                detail: "这份文件不是完整的 DSAE 产物，无法比对。",
                                storedFingerprint: "—",
                                fileFingerprint: fileFingerprint)
        }

        guard let digest = envelope.digest else {
            return VerifyResult(kind: .damaged,
                                detail: "产物里没有验证指纹，无法比对。",
                                storedFingerprint: "—",
                                fileFingerprint: fileFingerprint)
        }

        let storedFingerprint = shortFingerprint(digest)
        let actualDigest = sha256(candidate)

        if actualDigest == digest {
            return VerifyResult(kind: .identical,
                                detail: "这份文件与产物记录的内容完全一致，没有任何改动。",
                                storedFingerprint: storedFingerprint,
                                fileFingerprint: fileFingerprint)
        }

        return VerifyResult(kind: .tampered,
                            detail: "数据部分被改动了：这份文件的内容与产物记录不一致，属于被篡改。",
                            storedFingerprint: storedFingerprint,
                            fileFingerprint: fileFingerprint)
    }

    static func shortFingerprint(_ data: Data) -> String {
        let hex = hexEncode(sha256(data))
        return String(hex.prefix(8))
    }

    /// 只检查产物本身有没有损坏（不需要原文件）。
    static func selfCheck(_ payload: Data) -> VerifyResult {
        do {
            let envelope = try parse(payload)
            let bodyFingerprint = shortFingerprint(envelope.body)
            let stored = envelope.digest.map { shortFingerprint($0) } ?? "—"
            let modeText = envelope.mode == .random ? "随机加密" : "口令加密"
            return VerifyResult(
                kind: .identical,
                detail: "\(modeText)产物：头部校验与数据校验都通过，密文没有被改动。",
                storedFingerprint: stored,
                fileFingerprint: bodyFingerprint
            )
        } catch let error as DSAEError {
            switch error {
            case .damagedHeader:
                return VerifyResult(
                    kind: .damaged,
                    detail: "产物头部校验没通过：结构被改动，或文件没有完整传过来。",
                    storedFingerprint: "—",
                    fileFingerprint: "—"
                )
            case .damagedBody:
                return VerifyResult(
                    kind: .damaged,
                    detail: "产物数据部分校验没通过：密文被改动，这份产物已经损坏。",
                    storedFingerprint: "—",
                    fileFingerprint: "—"
                )
            default:
                return VerifyResult(
                    kind: .damaged,
                    detail: "这份文件不是完整的 DSAE 产物。",
                    storedFingerprint: "—",
                    fileFingerprint: "—"
                )
            }
        } catch {
            return VerifyResult(
                kind: .damaged,
                detail: "这份文件不是完整的 DSAE 产物。",
                storedFingerprint: "—",
                fileFingerprint: "—"
            )
        }
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

    /// 从 file.dsaetxt 取出 file
    static func baseName(fromSealed name: String) -> String {
        guard let range = name.range(of: ".dsae", options: .backwards) else {
            return (name as NSString).deletingPathExtension
        }
        return String(name[name.startIndex..<range.lowerBound])
    }
}
