import SwiftUI

enum DSTheme {
    static let accent = Color(red: 0.04, green: 0.46, blue: 0.60)
    static let accentBright = Color(red: 0.20, green: 0.78, blue: 0.86)
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct FieldShell<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                DSTheme.accent.opacity(0.20),
                Color.clear,
                DSTheme.accentBright.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 30)
    }
}

extension View {
    func dsaeToast(_ text: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let value = text.wrappedValue {
                Toast(text: value)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
