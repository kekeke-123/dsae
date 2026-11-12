import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var vault: Vault

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(DSTheme.accent)
                    Text("DSAE")
                        .font(.largeTitle.weight(.bold))
                    Text("Dynamic Semantic Autoencoder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("先设置一个口令，之后才能使用。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.top, 24)

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("口令规则")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(PasswordPolicy.ruleText)
                            .font(.subheadline)
                        Text("口令就是加密用的密钥来源，忘记后无法找回。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(spacing: 12) {
                        FieldShell {
                            SecureField("设置口令", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.weight(.medium))
                        }
                        FieldShell {
                            SecureField("再输一次确认", text: $confirmPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.weight(.medium))
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
                    create()
                } label: {
                    Text("设置口令并进入")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(DSTheme.accent)
                .controlSize(.large)
                .disabled(password.isEmpty || confirmPassword.isEmpty)
            }
            .padding(24)
        }
    }

    private func create() {
        guard password == confirmPassword else {
            errorMessage = "两次输入的口令不一致。"
            return
        }
        if let problem = vault.createPassword(password) {
            errorMessage = problem
            return
        }
        errorMessage = nil
    }
}
