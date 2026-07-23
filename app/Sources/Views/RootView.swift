import SwiftUI

/// Onglets racine : Modules (flux de test) | Logs (debug) | Réglages.
struct RootView: View {
    @EnvironmentObject private var debugLog: DebugLog

    var body: some View {
        TabView {
            NavigationStack {
                ModulesListView()
            }
            .tabItem { Label("Modules", systemImage: "puzzlepiece.extension") }

            NavigationStack {
                LogsView()
            }
            .tabItem { Label("Logs", systemImage: "terminal") }
            .badge(debugLog.errorCount)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
