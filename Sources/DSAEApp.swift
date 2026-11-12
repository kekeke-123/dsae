import SwiftUI

@main
struct DSAEApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var vault = Vault()

    var body: some View {
        ZStack {
            ScreenBackground()
            switch vault.phase {
            case .setup:
                OnboardingView()
            case .locked:
                UnlockView()
            case .unlocked:
                MainView()
            }
        }
        .environmentObject(vault)
    }
}

struct MainView: View {
    var body: some View {
        TabView {
            TextCryptView()
                .tabItem { Label("文本", systemImage: "text.alignleft") }

            FileCryptView()
                .tabItem { Label("文件", systemImage: "folder") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(DSTheme.accent)
    }
}
