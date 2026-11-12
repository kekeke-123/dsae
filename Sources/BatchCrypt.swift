import Foundation

struct BatchReport {
    var title: String
    var succeeded = 0
    var skipped = 0
    var failed = 0
    var notes: [String] = []
    var truncated = false

    var total: Int { succeeded + skipped + failed }

    mutating func note(_ text: String) {
        guard notes.count < 6 else { return }
        notes.append(text)
    }
}

/// 整文件夹批量加解密：就地处理，逐个文件读写，不把整夹内容读进内存。
enum BatchCrypt {

    static let maxFiles = 2000

    typealias ProgressHandler = (_ done: Int, _ total: Int) -> Void

    // MARK: - 批量加密

    static func encrypt(folder root: URL, password: String, random: Bool, progress: ProgressHandler) -> BatchReport {
        var report = BatchReport(title: random ? "文件夹随机加密" : "文件夹加密")

        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        let files = collectFiles(in: root)
        let planned = Array(files.prefix(maxFiles))
        report.truncated = files.count > maxFiles
        progress(0, planned.count)

        for (offset, file) in planned.enumerated() {
            defer { progress(offset + 1, planned.count) }

            let name = file.lastPathComponent

            if name.contains(".dsae") {
                report.skipped += 1
                report.note("跳过 \(name)：已经是 DSAE 产物")
                continue
            }

            let size = fileSize(file)
            if size == 0 {
                report.skipped += 1
                report.note("跳过 \(name)：空文件")
                continue
            }
            if size > DSAECrypto.maxBytes {
                report.skipped += 1
                report.note("跳过 \(name)：超过 200 MB")
                continue
            }

            do {
                let plain = try Data(contentsOf: file)
                let payload = random
                    ? try DSAECrypto.sealRandom(plain: plain, ext: file.pathExtension)
                    : try DSAECrypto.seal(plain: plain, password: password, ext: file.pathExtension)
                let target = file.deletingLastPathComponent()
                    .appendingPathComponent(DSAECrypto.sealedName(for: name))
                try? FileManager.default.removeItem(at: target)
                try payload.write(to: target, options: .atomic)
                report.succeeded += 1
            } catch {
                report.failed += 1
                report.note("失败 \(name)：\(error.localizedDescription)")
            }
        }

        return report
    }

    // MARK: - 批量还原

    static func decrypt(folder root: URL, candidates: [String], progress: ProgressHandler) -> BatchReport {
        var report = BatchReport(title: "文件夹还原")

        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        let files = collectFiles(in: root)
        let products = files.filter { $0.lastPathComponent.contains(".dsae") }
        let planned = Array(products.prefix(maxFiles))
        report.truncated = products.count > maxFiles
        progress(0, planned.count)

        for (offset, file) in planned.enumerated() {
            defer { progress(offset + 1, planned.count) }

            let name = file.lastPathComponent

            if fileSize(file) > DSAECrypto.maxBytes * 2 {
                report.skipped += 1
                report.note("跳过 \(name)：超过大小上限")
                continue
            }

            do {
                let payload = try Data(contentsOf: file)
                let opened = try DSAECrypto.open(payload, candidates: candidates)

                let base = DSAECrypto.baseName(fromSealed: name)
                let targetName: String
                if let restored = DSAECrypto.restoredName(fromSealed: name) {
                    targetName = restored
                } else if opened.ext.isEmpty {
                    targetName = base
                } else {
                    targetName = base + "." + opened.ext
                }

                let target = file.deletingLastPathComponent().appendingPathComponent(targetName)
                if FileManager.default.fileExists(atPath: target.path) {
                    report.skipped += 1
                    report.note("跳过 \(name)：\(targetName) 已存在，不覆盖")
                    continue
                }

                try opened.data.write(to: target, options: .atomic)
                report.succeeded += 1
            } catch {
                report.failed += 1
                report.note("失败 \(name)：\(error.localizedDescription)")
            }
        }

        return report
    }

    // MARK: - 扫描

    private static func collectFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile == true, values.isSymbolicLink != true {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
