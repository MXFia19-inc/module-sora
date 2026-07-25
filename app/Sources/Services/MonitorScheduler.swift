import Foundation
import BackgroundTasks

/// Surveillance planifiée : relance périodiquement un préréglage de test et
/// signale les régressions (via le webhook Discord).
///
/// iOS ne garantit pas l'exécution en arrière-plan : les lancements sont fiables
/// tant que l'app est ouverte, et « au mieux » via BGAppRefresh sinon.
@MainActor
final class MonitorScheduler: ObservableObject {
    static let taskIdentifier = "com.mxfia19.ModuleTester.monitor"

    @Published private(set) var isRunning = false
    @Published private(set) var lastRun: Date?
    @Published private(set) var lastOutcome: String?

    private let defaults = UserDefaults.standard
    private let lastRunKey = "monitorLastRun"

    init() {
        lastRun = defaults.object(forKey: lastRunKey) as? Date
    }

    /// Prochain lancement prévu selon l'intervalle configuré.
    func nextRun(settings: AppSettings) -> Date? {
        guard settings.monitorEnabled else { return nil }
        let interval = settings.monitorInterval
        guard let lastRun else { return Date() }
        return lastRun.addingTimeInterval(interval)
    }

    func isDue(settings: AppSettings) -> Bool {
        guard settings.monitorEnabled, !isRunning else { return false }
        guard let next = nextRun(settings: settings) else { return false }
        return Date() >= next
    }

    /// Lance un cycle de surveillance s'il est dû (appelé par le minuteur de l'UI).
    func tick(store: ModuleStore, tester: MassTester, presets: PresetStore,
              history: HistoryStore, debugLog: DebugLog, settings: AppSettings) async {
        guard isDue(settings: settings) else { return }
        await run(store: store, tester: tester, presets: presets,
                  history: history, debugLog: debugLog, settings: settings, source: "Monitor")
    }

    /// Exécute le test surveillé, enregistre l'historique et notifie si besoin.
    func run(store: ModuleStore, tester: MassTester, presets: PresetStore,
             history: HistoryStore, debugLog: DebugLog, settings: AppSettings,
             source: String = "Monitor") async {
        guard !isRunning, !tester.isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Modules à tester : ceux du préréglage choisi, sinon tous.
        let preset = presets.presets.first { $0.name == settings.monitorPresetName }
        let modules: [LoadedModule]
        var overrides: [String: TestCategory] = [:]
        var keywords: [String: String] = [:]
        if let preset {
            let ids = Set(preset.moduleIds)
            modules = store.modules.filter { ids.contains($0.id) }
            overrides = presets.categories(of: preset)
            keywords = preset.customKeywords
        } else {
            modules = store.modules
        }
        guard !modules.isEmpty else {
            lastOutcome = L("No module to monitor.")
            return
        }

        debugLog.append(.info, "Monitoring run started (\(modules.count) modules)", module: "Monitor")
        await tester.run(modules: modules, overrides: overrides, customKeywords: keywords,
                         debugLog: debugLog, settings: settings)

        let record = history.record(tester.reports, source: source)
        let diff = history.latestDiff
        lastRun = Date()
        defaults.set(lastRun, forKey: lastRunKey)

        let hasRegression = !(diff?.regressions.isEmpty ?? true)
        lastOutcome = hasRegression
            ? Lf("%@ regression(s)", "\(diff?.regressions.count ?? 0)")
            : "\(record.summary) OK"
        debugLog.append(hasRegression ? .error : .info,
                        "Monitoring: \(record.summary) OK, \(diff?.regressions.count ?? 0) regression(s)",
                        module: "Monitor")

        // Notification Discord : toujours, ou seulement en cas de régression.
        guard settings.hasWebhook else { return }
        if settings.monitorOnlyOnRegression && !hasRegression { return }
        do {
            try await tester.sendReportToDiscord(webhook: settings.discordWebhook,
                                                 diff: diff, source: source)
        } catch {
            debugLog.append(.error, "Monitoring webhook failed: \(error.localizedDescription)",
                            module: "Monitor")
        }
    }

    // MARK: - Arrière-plan (au mieux)

    /// Demande à iOS de réveiller l'app pour un cycle de surveillance.
    func scheduleBackgroundRefresh(settings: AppSettings) {
        guard settings.monitorEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(settings.monitorInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
