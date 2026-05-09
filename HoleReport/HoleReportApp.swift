import SwiftUI
import UIKit

@main
struct HoleReportApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var showSafetyWarning = true

    init() {
        // Access the singleton here so the Bundle shim is installed before
        // any view renders (earlier than a @StateObject which initialises lazily).
        _ = LanguageManager.shared

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor.systemGray
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showWelcome {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showWelcome = false
                        }
                        hasSeenWelcome = true
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }

                if showSafetyWarning {
                    SafetyWarningView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showSafetyWarning = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .onAppear {
                showWelcome = !hasSeenWelcome
            }
        }
    }
}
