import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject private var vault: Vault
    @State private var showChangePassword = false
    @State private var toast: String?

    private var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("口令", systemImage: "key.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("已设置，正在使用中")
                                .font(.subheadline)

                            Button("修改口令") {
                                showChangePassword = true
                            }
                            .buttonStyle(.glass)

                            Text("修改前用旧口令加密的文件、文本仍然可以还原：App 会自动保留最近 5 个旧口令用于兼容。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("面容 ID", systemImage: "faceid")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Toggle("用面容 ID 解锁", isOn: $vault.faceIDEnabled)
                                .disabled(!biometricsAvailable)

                            if !biometricsAvailable {
                                Text("这台设备没有可用的面容 ID。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("面容 ID 只是解锁手段；口令仍然是加密密钥的来源。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            Text("已 \(vault.daysSincePassword) 天没有输入口令，还有 \(vault.daysUntilRefresh) 天需要重新输入一次。")
                                .font(.caption)
                                .foregroundStyle(vault.requiresPasswordRefresh ? .red : .secondary)

                            Text("规则：连续 7 天只用面容 ID、没有输入过任何一次口令，下一次就必须输入口令，防止忘记。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("算法", systemImage: "function")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            infoRow("口令派生", "PBKDF2-HMAC-SHA256，120,000 次迭代，16 字节随机盐")
                            infoRow("加密", "AES-256-GCM，带认证，改一位就无法还原")
                            infoRow("文本格式", "十六进制（不使用 Base64）")
                            infoRow("文件命名", "file.txt → file.dsaetxt")
                            infoRow("随机加密", "随机密钥用完即丢，产物不可还原，只能验证")
                            infoRow("指纹", "SHA-256（原文），写在产物头部")
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("隐私", systemImage: "hand.raised.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("App 内没有任何网络请求代码，不上传、不统计、不写日志。所有运算在本机完成，密钥只在运行内存里。")
                                .font(.caption)
                        }
                    }

                    Button(role: .destructive) {
                        vault.lock()
                    } label: {
                        Text("立即锁定")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(18)
            }
            .background(ScreenBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .dsaeToast($toast)
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView { message in
                    showToast(message)
                }
                .environmentObject(vault)
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { self.toast = nil }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var vault: Vault
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var done = false

    var completion: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("新口令规则")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(PasswordPolicy.ruleText)
                                .font(.caption)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 12) {
                            FieldShell {
                                SecureField("新口令", text: $newPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            FieldShell {
                                SecureField("再输一次", text: $confirmPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        save()
                    } label: {
                        Text("保存新口令")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DSTheme.accent)
                    .controlSize(.large)
                    .disabled(newPassword.isEmpty || confirmPassword.isEmpty)
                }
                .padding(18)
            }
            .background(ScreenBackground())
            .navigationTitle("修改口令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的口令不一致。"
            return
        }
        if let problem = vault.changePassword(to: newPassword) {
            errorMessage = problem
            return
        }
        errorMessage = nil
        completion("口令已更新")
        dismiss()
    }
}
