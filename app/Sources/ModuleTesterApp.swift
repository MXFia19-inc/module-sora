import SwiftUI
import BackgroundTasks

@main
struct ModuleTesterApp: App {
    @StateObject private var moduleStore = ModuleStore()
    @StateObject private var debugLog = DebugLog()
    @StateObject private var settings = AppSettings()
    @StateObject private var massTester = MassTester()
    @StateObject private var presetStore = PresetStore()
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var monitor = MonitorScheduler()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(moduleStore)
                .environmentObject(debugLog)
                .environmentObject(settings)
                .environmentObject(massTester)
                .environmentObject(presetStore)
                .environmentObject(historyStore)
                .environmentObject(monitor)
                .preferredColorScheme(.dark)
                .id(settings.language)
                .onChange(of: scenePhase) { phase in
                    // Demande un réveil en arrière-plan quand l'app passe en veille.
                    if phase == .background { monitor.scheduleBackgroundRefresh(settings: settings) }
                }
        }
        // Exécution « au mieux » accordée par iOS : un cycle de surveillance.
        .backgroundTask(.appRefresh(MonitorScheduler.taskIdentifier)) {
            await monitor.run(store: moduleStore, tester: massTester, presets: presetStore,
                              history: historyStore, debugLog: debugLog, settings: settings,
                              source: "Background")
            await monitor.scheduleBackgroundRefresh(settings: settings)
        }
    }
}
