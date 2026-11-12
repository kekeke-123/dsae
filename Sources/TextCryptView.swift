import SwiftUI
import UIKit

struct TextCryptView: View {
    @State private var mode: CryptMode = .encode
    @State private var input: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var output: String = ""
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("模式", selection: $mode) {
                        ForEach(CryptMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    SectionCard(title: mode == .encode ? "原文" : "密文") {
                        TextEditor(text: $input)
                            .frame(minHeight: 150)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )

                        HStack(spacing: 12) {
                            Text("\(input.count) 字符")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if mode == .decode {
                                Button("粘贴") {
                                    if let string = UIPasteboard.general.string {
                                        input = string
                                    }
                                }
                                .font(.footnote)
                            }
                            Button("清空") {
                                input = ""
                                output = ""
                            }
                            .font(.footnote)
                            .disabled(input.isEmpty)
                        }
                    }

                    SectionCard(title: "口令") {
                        SecureField(mode == .encode ? "设置口令" : "输入口令", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )

                        if mode == .encode {
                            SecureField("再输一次以确认", text: $confirmPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                        }

                        Text("口令不会离开这台设备；忘记口令后，任何人都无法还原内容。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        run()
                    } label: {
                        Text(mode == .encode ? "编码" : "还原")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(input.isEmpty || password.isEmpty)

                    if !output.isEmpty {
                        SectionCard(title: mode == .encode ? "密文（可直接复制分享）" : "还原结果") {
                            Text(output)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )

                            HStack {
                                Text("\(output.count) 字符")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("复制") {
                                    UIPasteboard.general.string = output
                                    showToast("已复制")
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        }
                    }

                    Text("DSAE · AES-256-GCM 认证加密 · 全程离线")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DSAE")
            .navigationBarTitleDisplayMode(.inline)
            .alert("提示", isPresented: $showAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color(.label).opacity(0.85))
                        )
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
    }

    private func run() {
        do {
            switch mode {
            case .encode:
                guard password == confirmPassword else { throw DSAEError.passwordMismatch }
                output = try DSAECipher.encryptText(input, password: password)
                showToast("编码完成")
            case .decode:
                output = try DSAECipher.decryptText(input, password: password)
                showToast("还原完成")
            }
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}
