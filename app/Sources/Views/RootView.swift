import SwiftUI

/// Onglets racine : Modules (flux de test) | Test | Logs (debug) | Réglages.
struct RootView: View {
    @EnvironmentObject private var debugLog: DebugLog
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tester: MassTester
    @EnvironmentObject private var presets: PresetStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var monitor: MonitorScheduler

    /// Vérifie toutes les minutes si un cycle de surveillance est dû.
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            NavigationStack {
                ModulesListView()
            }
            .tabItem { Label(L("Modules"), systemImage: "puzzlepiece.extension") }

            NavigationStack {
                MassTestView()
            }
            .tabItem { Label(L("Test"), systemImage: "checklist") }

            NavigationStack {
                LogsView()
            }
            .tabItem { Label(L("Logs"), systemImage: "terminal") }
            .badge(debugLog.errorCount)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(L("Settings"), systemImage: "gearshape") }
        }
        .onReceive(tick) { _ in
            Task {
                await monitor.tick(store: store, tester: tester, presets: presets,
                                   history: history, debugLog: debugLog, settings: settings)
            }
        }
    }
}
