import Foundation

/// État d'un module lors d'un test (instantané persistable).
struct ModuleSnapshot: Codable, Hashable {
    var moduleName: String
    var category: String
    var keyword: String
    var overall: String
    /// Statut par étape (nom d'étape → statut brut).
    var steps: [String: String]
    var successCount: Int
    var stepCount: Int
}

/// Un lancement de test en masse, conservé dans l'historique.
struct TestRunRecord: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    /// Origine du lancement (« Manual », « Monitor »…).
    var source: String = "Manual"
    var modules: [ModuleSnapshot]

    var okCount: Int { modules.filter { $0.overall == StepStatus.success.rawValue }.count }
    var total: Int { modules.count }

    var summary: String { "\(okCount)/\(total)" }
}

/// Différence entre deux lancements.
struct RunDiff {
    /// Étapes passées de succès à échec (« module · étape »).
    var regressions: [String] = []
    /// Étapes réparées depuis le lancement précédent.
    var fixes: [String] = []
    /// Modules présents seulement dans le nouveau lancement.
    var added: [String] = []
    /// Modules absents du nouveau lancement.
    var removed: [String] = []

    var isEmpty: Bool {
        regressions.isEmpty && fixes.isEmpty && added.isEmpty && removed.isEmpty
    }

    /// Compare un nouveau lancement au précédent.
    static func between(new: TestRunRecord, old: TestRunRecord) -> RunDiff {
        var diff = RunDiff()
        let oldByName = Dictionary(uniqueKeysWithValues: old.modules.map { ($0.moduleName, $0) })
        let newByName = Dictionary(uniqueKeysWithValues: new.modules.map { ($0.moduleName, $0) })

        for module in new.modules {
            guard let previous = oldByName[module.moduleName] else {
                diff.added.append(module.moduleName)
                continue
            }
            for (step, status) in module.steps {
                let before = previous.steps[step]
                if before == StepStatus.success.rawValue, status == StepStatus.failure.rawValue {
                    diff.regressions.append("\(module.moduleName) · \(step)")
                } else if before == StepStatus.failure.rawValue, status == StepStatus.success.rawValue {
                    diff.fixes.append("\(module.moduleName) · \(step)")
                }
            }
        }
        for module in old.modules where newByName[module.moduleName] == nil {
            diff.removed.append(module.moduleName)
        }
        diff.regressions.sort()
        diff.fixes.sort()
        return diff
    }
}
