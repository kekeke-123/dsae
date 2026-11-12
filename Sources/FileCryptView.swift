import SwiftUI

struct FileCryptView: View {
    @State private var mode: CryptMode = .encode
    @State private var pickedURL: URL?
    @State private var pickedInfo: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var resultURL: URL?
    @State private var resultInfo: String = ""
    @State private var busy = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var alertMessage: String?
    @State private var showAlert = false

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
                    .onChange(of: mode) { _ in
                        resultURL = nil
                        resultInfo = ""
                    }

                    SectionCard(title: mode == .encode ? "选择要编码的文件" : "选择 .dsae 文件") {
                        Button {
                            showImporter = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.plus")
                                Text(pickedURL == nil ? "从「文件」中选择" : "重新选择")
                                Spacer()
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)

                        if pickedURL != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pickedURL?.lastPathComponent ?? "")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(pickedInfo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

                        Text("大文件在后台线程运算，超过 200 MB 会被拒绝。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        process()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "处理中…" : (mode == .encode ? "编码文件" : "还原文件"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(pickedURL == nil || password.isEmpty || busy)

                    if let resultURL {
                        SectionCard(title: "产物") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(resultURL.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(resultInfo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                showExporter = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("保存到「文件」")
                                }
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.05, green: 0.47, blue: 0.60))
                        }
                    }

                    Text("文件不会上传到任何服务器；DSAE 没有联网代码。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("文件保险箱")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showImporter) {
                DocumentPicker(mode: .importing) { url in
                    showImporter = false
                    guard let url else { return }
                    pickedURL = url
                    resultURL = nil
                    resultInfo = ""
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    pickedInfo = DSAECipher.humanSize(size) + " · " + url.pathExtension.uppercased()
                }
            }
            .sheet(isPresented: $showExporter) {
                Group {
                    if let resultURL {
                        DocumentPicker(mode: .exporting([resultURL])) { _ in
                            showExporter = false
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func process() {
        guard let url = pickedURL else { return }
        if mode == .encode && password != confirmPassword {
            alertMessage = DSAEError.passwordMismatch.localizedDescription
            showAlert = true
            return
        }

        busy = true
        let targetMode = mode
        let targetURL = url
        let pwd = password

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputURL: URL
                if targetMode == .encode {
                    outputURL = try DSAECipher.encryptFile(at: targetURL, password: pwd)
                } else {
                    outputURL = try DSAECipher.decryptFile(at: targetURL, password: pwd)
                }
                let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                DispatchQueue.main.async {
                    busy = false
                    resultURL = outputURL
                    resultInfo = DSAECipher.humanSize(size)
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}
