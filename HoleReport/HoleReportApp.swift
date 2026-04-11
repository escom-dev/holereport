import SwiftUI
import UIKit

@main
struct HoleReportApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    init() {
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
            }
            .onAppear {
                showWelcome = !hasSeenWelcome
            }
        }
    }
}
