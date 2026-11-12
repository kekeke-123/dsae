import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.47, blue: 0.60))
                        Text("DSAE")
                            .font(.title2.weight(.bold))
                        Text("Dynamic Semantic Autoencoder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("v\(version) · 纯本地")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)

                    SectionCard(title: "它做什么") {
                        Text("把文本或文件编码成一段无法直接阅读的密文；只有输入同一口令，才能还原成原始内容。产物可以复制、保存、发给自己，但离开设备后也只是一段密文。")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }

                    SectionCard(title: "算法") {
                        row("口令派生", "PBKDF2-HMAC-SHA256，120,000 次迭代，16 字节随机盐")
                        Divider()
                        row("加密算法", "AES-256-GCM（带认证，篡改会被检测出来）")
                        Divider()
                        row("密钥长度", "256 位，每次编码重新生成盐与随机 nonce")
                        Divider()
                        row("文件格式", "魔数 DSAE1 + 盐 + nonce + 密文 + 认证标签")
                        Divider()
                        row("文本格式", "DSAE1- 前缀 + Base64")
                    }

                    SectionCard(title: "隐私") {
                        Text("App 内没有任何网络请求代码，不申请网络权限，不上传、不统计、不写日志。所有运算通过 CryptoKit 在本机完成，密钥只存在于运行内存中。")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("唯一无法挽回的事情：口令丢失后，内容无法恢复。请把口令单独记在可靠的地方。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("DSAE · 只在你的设备上做运算")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ left: String, _ right: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(left)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(right)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
