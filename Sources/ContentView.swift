import SwiftUI

enum CryptMode: String, CaseIterable, Identifiable {
    case encode
    case decode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encode: return "编码"
        case .decode: return "还原"
        }
    }

    var subtitle: String {
        switch self {
        case .encode: return "原文 → 密文"
        case .decode: return "密文 → 原文"
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            TextCryptView()
                .tabItem { Label("文本", systemImage: "text.alignleft") }

            FileCryptView()
                .tabItem { Label("文件", systemImage: "folder") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .tint(Color(red: 0.05, green: 0.47, blue: 0.60))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.47, blue: 0.60))
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
