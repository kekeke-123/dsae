import SwiftUI
import UIKit

enum CryptDirection: String, CaseIterable, Identifiable {
    case encode
    case decode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encode: return "加密"
        case .decode: return "还原"
        }
    }
}

struct TextCryptView: View {
    @EnvironmentObject private var vault: Vault

    @State private var direction: CryptDirection = .encode
    @State private var input = ""
    @State private var output = ""
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("方式", selection: $direction) {
                        ForEach(CryptDirection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 2)
                    .onChange(of: direction) {
                        self.output = ""
                        self.errorMessage = nil
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(direction == .encode ? "原文" : "十六进制密文")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(input.count) 字符")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            TextEditor(text: $input)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            HStack(spacing: 14) {
                                Button("粘贴") {
                                    if let string = UIPasteboard.general.string {
                                        input = string
                                    }
                                }
                                .buttonStyle(.glass)

                                Button("清空") {
                                    input = ""
                                    output = ""
                                }
                                .buttonStyle(.glass)
                                .disabled(input.isEmpty)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("使用当前口令", systemImage: "key.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("口令在「设置」里可以修改；修改前加密的旧文本，App 会自动用保留的旧口令尝试还原。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        run()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(direction == .encode ? "加密这段文字" : "还原这段文字")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DSTheme.accent)
                    .controlSize(.large)
                    .disabled(input.isEmpty || busy)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !output.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(direction == .encode ? "密文（十六进制）" : "还原结果")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(output)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack {
                                    Text("\(output.count) 字符")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("复制") {
                                        UIPasteboard.general.string = output
                                        showToast("已复制")
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(ScreenBackground())
            .navigationTitle("文本")
            .navigationBarTitleDisplayMode(.inline)
            .dsaeToast($toast)
        }
    }

    private func run() {
        // PBKDF2 要跑 12 万次，放主线程会卡住界面。
        let isEncode = direction == .encode
        let password = vault.password
        let candidates = vault.encryptionCandidates()
        let text = input

        busy = true
        errorMessage = nil
        output = ""

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if isEncode {
                    let payload = try DSAECrypto.seal(plain: Data(text.utf8), password: password, ext: "")
                    let hex = DSAECrypto.hexEncode(payload)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.output = hex
                        self.showToast("已加密")
                    }
                } else {
                    guard let payload = DSAECrypto.hexDecode(text) else {
                        throw DSAEError.badFormat
                    }
                    let opened = try DSAECrypto.open(payload, candidates: candidates)
                    guard let plain = String(data: opened.data, encoding: .utf8) else {
                        throw DSAEError.badFormat
                    }
                    DispatchQueue.main.async {
                        self.busy = false
                        self.output = plain
                        self.showToast("已还原")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.errorMessage = error.localizedDescription
                    self.output = ""
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { self.toast = nil }
        }
    }
}
