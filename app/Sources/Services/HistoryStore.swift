import Foundation

/// Conserve les derniers lancements de test (Documents/history.json) et fournit
/// la comparaison avec le lancement précédent.
@MainActor
final class HistoryStore: ObservableObject {
    /// Du plus récent au plus ancien.
    @Published private(set) var runs: [TestRunRecord] = []

    private let fileURL: URL
    private let maxRuns = 30

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        runs = (try? JSONDecoder().decode([TestRunRecord].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(runs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Enregistre un lancement à partir des rapports du testeur.
    @discardableResult
    func record(_ reports: [ModuleTestReport], source: String = "Manual") -> TestRunRecord {
        let snapshots = reports.map { report in
            ModuleSnapshot(
                moduleName: report.module.name,
                category: report.category.label,
                keyword: report.keyword,
                overall: report.overall.rawValue,
                steps: Dictionary(uniqueKeysWithValues: report.steps.map { ($0.name, $0.status.rawValue) }),
                successCount: report.successCount,
                stepCount: report.steps.count
            )
        }
        let record = TestRunRecord(source: source, modules: snapshots)
        runs.insert(record, at: 0)
        if runs.count > maxRuns { runs.removeLast(runs.count - maxRuns) }
        persist()
        return record
    }

    /// Comparaison d'un lancement avec celui qui le précède dans l'historique.
    func diff(for run: TestRunRecord) -> RunDiff? {
        guard let index = runs.firstIndex(where: { $0.id == run.id }),
              index + 1 < runs.count else { return nil }
        return RunDiff.between(new: run, old: runs[index + 1])
    }

    /// Comparaison du dernier lancement avec le précédent.
    var latestDiff: RunDiff? {
        guard let latest = runs.first else { return nil }
        return diff(for: latest)
    }

    func remove(_ run: TestRunRecord) {
        runs.removeAll { $0.id == run.id }
        persist()
    }

    func clear() {
        runs.removeAll()
        persist()
    }
}
