import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var vault: Vault

    @State private var entered = ""
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(DSTheme.accent)

            Text("DSAE")
                .font(.largeTitle.weight(.bold))

            if vault.requiresPasswordRefresh {
                Text("距上次输入口令已 \(vault.daysSincePassword) 天，本次必须输入口令（每 7 天至少一次，防止忘记）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            FieldShell {
                SecureField("输入口令", text: $entered)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.weight(.medium))
                    .submitLabel(.go)
                    .onSubmit { unlock() }
            }
            .padding(.horizontal, 28)

            Button {
                unlock()
            } label: {
                Text("解锁")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(DSTheme.accent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .disabled(entered.isEmpty || working)

            if vault.faceIDEnabled && !vault.requiresPasswordRefresh {
                Button {
                    Task { await faceID() }
                } label: {
                    Label("用面容 ID 解锁", systemImage: "faceid")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(working)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer(minLength: 40)
        }
        .padding(.vertical, 24)
        .task {
            if vault.faceIDEnabled && !vault.requiresPasswordRefresh {
                await faceID()
            }
        }
    }

    private func unlock() {
        working = true
        defer { working = false }
        if let problem = vault.unlock(with: entered) {
            errorMessage = problem
            entered = ""
        } else {
            errorMessage = nil
            entered = ""
        }
    }

    private func faceID() async {
        working = true
        let problem = await vault.unlockWithBiometrics()
        working = false
        errorMessage = problem
    }
}
