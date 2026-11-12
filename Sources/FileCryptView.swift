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
    @State private var verifyReport: VerifyResult?

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
                        self.verifyReport = nil
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
                                     ? "随机密钥用完即丢弃：产物无法还原，只能拿去验证文件有没有被改。"
                                     : "用当前口令加密，随时可以用口令还原。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if task == .verify {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("把产物和原文件一起发给对方，对方在这个 App 里选两份文件比对。验证只用指纹，不需要口令。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                pickRow(title: "DSAE 产物", url: sealedURL) { showSealedPicker = true }
                                pickRow(title: "要对比的文件（可选）", url: candidateURL) { showCandidatePicker = true }

                                Text(candidateURL == nil
                                     ? "只选了产物：会检查产物本身有没有损坏。再选一个文件，才能判断内容是否被篡改。"
                                     : "两份都选好了：可以判断内容是「一致」还是「被篡改」。")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
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
                                     : "还原时会去掉 .dsae，恢复成原来的名字。")
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

                    if let report = verifyReport {
                        verdictCard(report)
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
                    self.verifyReport = nil
                }
            }
            .sheet(isPresented: $showSealedPicker) {
                DocumentPicker(mode: .importing) { url in
                    self.showSealedPicker = false
                    guard let url else { return }
                    self.sealedURL = url
                    self.verifyReport = nil
                }
            }
            .sheet(isPresented: $showCandidatePicker) {
                DocumentPicker(mode: .importing) { url in
                    self.showCandidatePicker = false
                    guard let url else { return }
                    self.candidateURL = url
                    self.verifyReport = nil
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

    // MARK: - 结论卡片

    @ViewBuilder
    private func verdictCard(_ report: VerifyResult) -> some View {
        let isSelfCheck = candidateURL == nil
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(verdictTitle(report.kind, selfCheck: isSelfCheck),
                      systemImage: verdictIcon(report.kind))
                    .font(.headline)
                    .foregroundStyle(verdictColor(report.kind))

                Text(report.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Text("产物记录指纹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(report.storedFingerprint)
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Text(isSelfCheck ? "密文指纹" : "这份文件指纹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(report.fileFingerprint)
                        .font(.system(.caption, design: .monospaced))
                }

                Text("指纹取 SHA-256 前 8 位，可直接肉眼核对。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func verdictTitle(_ kind: VerifyKind, selfCheck: Bool) -> String {
        switch kind {
        case .identical: return selfCheck ? "完好" : "一致"
        case .tampered: return "篡改"
        case .damaged: return "损坏"
        }
    }

    private func verdictIcon(_ kind: VerifyKind) -> String {
        switch kind {
        case .identical: return "checkmark.seal.fill"
        case .tampered: return "exclamationmark.triangle.fill"
        case .damaged: return "xmark.seal.fill"
        }
    }

    private func verdictColor(_ kind: VerifyKind) -> Color {
        switch kind {
        case .identical: return .green
        case .tampered: return .orange
        case .damaged: return .red
        }
    }

    // MARK: - 状态

    private var canRun: Bool {
        switch task {
        case .encode, .restore:
            return sourceURL != nil
        case .verify:
            return sealedURL != nil
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
        verifyReport = nil
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
                    let plain = try Self.readData(url, limit: DSAECrypto.maxBytes)
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
                            ? "\(DSAECrypto.humanSize(payload.count)) · 随机加密，不可还原，可验证"
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
                    let payload = try Self.readData(url, limit: DSAECrypto.maxBytes * 2)
                    let opened = try DSAECrypto.open(payload, candidates: candidates)
                    let baseName = DSAECrypto.baseName(fromSealed: url.lastPathComponent)
                    let name: String
                    if let restored = DSAECrypto.restoredName(fromSealed: url.lastPathComponent) {
                        name = restored
                    } else if opened.ext.isEmpty {
                        name = baseName
                    } else {
                        name = baseName + "." + opened.ext
                    }
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
            guard let sealed = sealedURL else { return }
            let candidate = candidateURL
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let payload = try Self.readData(sealed, limit: DSAECrypto.maxBytes * 2)
                    let report: VerifyResult
                    if let candidate {
                        let data = try Self.readData(candidate, limit: DSAECrypto.maxBytes * 2)
                        report = DSAECrypto.verify(payload, candidate: data)
                    } else {
                        report = DSAECrypto.selfCheck(payload)
                    }
                    DispatchQueue.main.async {
                        self.busy = false
                        self.verifyReport = report
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

    private static func readData(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > limit {
            throw DSAEError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw DSAEError.tooLarge }
        return data
    }

    private static func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }
}
