import SwiftUI

enum FileTask: String, CaseIterable, Identifiable {
    case encode
    case restore
    case verify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encode: return "加密"
        case .restore: return "还原"
        case .verify: return "验证"
        }
    }
}

struct FileCryptView: View {
    @EnvironmentObject private var vault: Vault

    @State private var task: FileTask = .encode
    @State private var randomMode = false

    @State private var sourceURL: URL?
    @State private var sealedURL: URL?
    @State private var candidateURL: URL?

    @State private var resultURL: URL?
    @State private var resultNote = ""
    @State private var verifyResult: Bool?

    @State private var busy = false
    @State private var errorMessage: String?
    @State private var toast: String?

    @State private var showSourcePicker = false
    @State private var showSealedPicker = false
    @State private var showCandidatePicker = false
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("方式", selection: $task) {
                        ForEach(FileTask.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: task) {
                        self.resultURL = nil
                        self.resultNote = ""
                        self.verifyResult = nil
                        self.errorMessage = nil
                    }

                    if task == .encode {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("加密方式", selection: $randomMode) {
                                    Text("口令加密").tag(false)
                                    Text("随机加密").tag(true)
                                }
                                .pickerStyle(.segmented)

                                Text(randomMode
                                     ? "随机密钥用完即丢弃：这份产物无法还原，只能用来验证文件是否被改过。"
                                     : "用当前口令加密，随时可以用口令还原。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if task == .verify {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("选择一个 .dsae 产物，再选一个文件，检查它是不是那份原始文件。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                pickRow(title: "产物", url: sealedURL) { showSealedPicker = true }
                                pickRow(title: "对比的文件", url: candidateURL) { showCandidatePicker = true }
                            }
                        }
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                pickRow(
                                    title: task == .encode ? "原始文件" : "DSAE 产物",
                                    url: sourceURL
                                ) {
                                    showSourcePicker = true
                                }

                                Text(task == .encode
                                     ? "命名规则：file.txt → file.dsaetxt"
                                     : "还原时会把 .dsae 去掉，恢复成原来的名字。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        perform()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(actionTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DSTheme.accent)
                    .controlSize(.large)
                    .disabled(!canRun || busy)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let verifyResult {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(verifyResult ? "一致" : "不一致",
                                      systemImage: verifyResult ? "checkmark.seal.fill" : "xmark.seal.fill")
                                    .font(.headline)
                                    .foregroundStyle(verifyResult ? Color.green : Color.red)
                                Text(verifyResult
                                     ? "这份文件和产物记录的内容完全相同。"
                                     : "这份文件和产物记录的内容不同，可能被改过或不是同一个文件。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let resultURL {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("产物")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(resultURL.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(resultNote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showExport = true
                                } label: {
                                     Label("保存到「文件」", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(ScreenBackground())
            .navigationTitle("文件")
            .navigationBarTitleDisplayMode(.inline)
            .dsaeToast($toast)
            .sheet(isPresented: $showSourcePicker) {
                DocumentPicker(mode: .importing) { url in
                    self.showSourcePicker = false
                    guard let url else { return }
                    self.sourceURL = url
                    self.resultURL = nil
                    self.resultNote = ""
                    self.verifyResult = nil
                }
            }
            .sheet(isPresented: $showSealedPicker) {
                DocumentPicker(mode: .importing) { url in
                    self.showSealedPicker = false
                    guard let url else { return }
                    self.sealedURL = url
                    self.verifyResult = nil
                }
            }
            .sheet(isPresented: $showCandidatePicker) {
                DocumentPicker(mode: .importing) { url in
                    self.showCandidatePicker = false
                    guard let url else { return }
                    self.candidateURL = url
                    self.verifyResult = nil
                }
            }
            .sheet(isPresented: $showExport) {
                Group {
                    if let resultURL {
                        DocumentPicker(mode: .exporting([resultURL])) { _ in
                            self.showExport = false
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - 状态

    private var canRun: Bool {
        switch task {
        case .encode, .restore:
            return sourceURL != nil
        case .verify:
            return sealedURL != nil && candidateURL != nil
        }
    }

    private var actionTitle: String {
        if busy { return "处理中…" }
        switch task {
        case .encode: return randomMode ? "随机加密" : "加密文件"
        case .restore: return "还原文件"
        case .verify: return "验证文件"
        }
    }

    private func pickRow(title: String, url: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: url == nil ? "doc.badge.plus" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(DSTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url?.lastPathComponent ?? "点击选择")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 执行

    private func perform() {
        errorMessage = nil
        verifyResult = nil
        resultURL = nil
        resultNote = ""

        switch task {
        case .encode:
            guard let url = sourceURL else { return }
            let useRandom = randomMode
            let password = vault.password
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let plain = try Self.readData(url)
                    let payload: Data
                    if useRandom {
                        payload = try DSAECrypto.sealRandom(plain: plain, ext: url.pathExtension)
                    } else {
                        payload = try DSAECrypto.seal(plain: plain, password: password, ext: url.pathExtension)
                    }
                    let name = DSAECrypto.sealedName(for: url.lastPathComponent)
                    let output = try Self.writeTemp(payload, name: name)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.resultURL = output
                        self.resultNote = useRandom
                            ? "\(DSAECrypto.humanSize(payload.count)) · 随机加密，不可还原"
                            : "\(DSAECrypto.humanSize(payload.count)) · 口令加密"
                        self.showToast("已生成 \(name)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }

        case .restore:
            guard let url = sourceURL else { return }
            let candidates = vault.encryptionCandidates()
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let payload = try Self.readData(url)
                    let opened = try DSAECrypto.open(payload, candidates: candidates)
                    let name = DSAECrypto.restoredName(fromSealed: url.lastPathComponent)
                        ?? Self.fallbackName(ext: opened.ext)
                    let output = try Self.writeTemp(opened.data, name: name)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.resultURL = output
                        self.resultNote = "\(DSAECrypto.humanSize(opened.data.count)) · 已还原"
                        self.showToast("已还原为 \(name)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }

        case .verify:
            guard let sealed = sealedURL, let candidate = candidateURL else { return }
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let payload = try Self.readData(sealed)
                    let data = try Self.readData(candidate)
                    let same = try DSAECrypto.matches(payload, candidate: data)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.verifyResult = same
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { self.toast = nil }
        }
    }

    // MARK: - 工具

    private static func readData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > DSAECrypto.maxBytes * 2 {
            throw DSAEError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= DSAECrypto.maxBytes * 2 else { throw DSAEError.tooLarge }
        return data
    }

    private static func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fallbackName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        return ext.isEmpty ? "DSAE-还原-\(stamp).bin" : "DSAE-还原-\(stamp).\(ext)"
    }
}
