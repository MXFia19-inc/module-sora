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
    /// Identifiant du module (son scriptUrl). Absent des lancements enregistrés
    /// avant son ajout : on retombe alors sur le nom.
    var moduleID: String? = nil

    /// Identité du module dans les comparaisons. Le nom ne suffit pas : un même
    /// module peut être installé depuis deux sources (Luna et GitHub, p. ex.).
    var key: String { moduleID ?? moduleName }

    /// Hôte du script, pour distinguer deux modules homonymes.
    var host: String? { moduleID.flatMap { URL(string: $0)?.host } }
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

    /// Nom affichable d'un module ; l'hôte de son script est ajouté quand un
    /// autre module du lancement porte le même nom.
    func displayName(of module: ModuleSnapshot) -> String {
        let homonyms = modules.filter { $0.moduleName == module.moduleName }.count
        guard homonyms > 1, let host = module.host else { return module.moduleName }
        return "\(module.moduleName) (\(host))"
    }
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
    ///
    /// Pas de `Dictionary(uniqueKeysWithValues:)` ici : il fait planter l'app dès
    /// que deux modules partagent une clé, ce qui arrive avec deux modules
    /// homonymes (ou un historique enregistré avant que l'id n'y figure).
    static func between(new: TestRunRecord, old: TestRunRecord) -> RunDiff {
        var diff = RunDiff()
        let oldByKey = Dictionary(old.modules.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        // Lancements enregistrés sans id : rapprochement par nom.
        let oldByName = Dictionary(old.modules.filter { $0.moduleID == nil }.map { ($0.moduleName, $0) },
                                   uniquingKeysWith: { first, _ in first })
        var matchedOld = Set<String>()

        for module in new.modules {
            let name = new.displayName(of: module)
            guard let previous = oldByKey[module.key] ?? oldByName[module.moduleName] else {
                diff.added.append(name)
                continue
            }
            matchedOld.insert(previous.key)
            for (step, status) in module.steps {
                let before = previous.steps[step]
                if before == StepStatus.success.rawValue, status == StepStatus.failure.rawValue {
                    diff.regressions.append("\(name) · \(step)")
                } else if before == StepStatus.failure.rawValue, status == StepStatus.success.rawValue {
                    diff.fixes.append("\(name) · \(step)")
                }
            }
        }
        for module in old.modules where !matchedOld.contains(module.key) {
            diff.removed.append(old.displayName(of: module))
        }
        // Entrées uniques : les listes de l'écran Historique les utilisent comme identifiants.
        diff.regressions = unique(diff.regressions).sorted()
        diff.fixes = unique(diff.fixes).sorted()
        diff.added = unique(diff.added)
        diff.removed = unique(diff.removed)
        return diff
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
