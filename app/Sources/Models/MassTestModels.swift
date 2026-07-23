import SwiftUI

/// Catégorie de test déduite du champ `type` d'un module.
enum TestCategory: String, CaseIterable, Identifiable {
    case anime, film, serie, manga
    var id: String { rawValue }

    var label: String {
        switch self {
        case .anime: return "Anime"
        case .film: return "Film"
        case .serie: return "Série"
        case .manga: return "Manga"
        }
    }

    /// Déduit la catégorie depuis le `type` du manifest (priorité manga > anime > film > série).
    static func from(type: String?) -> TestCategory {
        let t = (type ?? "").lowercased()
        if t.contains("manga") || t.contains("scan") { return .manga }
        if t.contains("anime") { return .anime }
        if t.contains("movie") || t.contains("film") { return .film }
        if t.contains("show") || t.contains("serie") || t.contains("série") || t.contains("tv") { return .serie }
        return .anime
    }
}

enum StepStatus: String {
    case pending, running, success, failure, skipped

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "ellipsis.circle"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        case .skipped: return .orange
        }
    }
}

/// Une étape du pipeline de test (Chargement, Recherche, Détails, Épisodes, Flux).
struct TestStep: Identifiable {
    let name: String
    var status: StepStatus = .pending
    var detail: String?
    var durationMs: Int?
    var id: String { name }
}

/// Rapport de test d'un module.
struct ModuleTestReport: Identifiable {
    let module: LoadedModule
    let category: TestCategory
    let keyword: String
    var steps: [TestStep]
    var startedAt: Date?

    var id: String { module.id }

    static let stepNames = ["Chargement", "Recherche", "Détails", "Épisodes", "Flux"]

    init(module: LoadedModule, category: TestCategory, keyword: String) {
        self.module = module
        self.category = category
        self.keyword = keyword
        self.steps = Self.stepNames.map { TestStep(name: $0) }
    }

    subscript(_ name: String) -> TestStep? {
        get { steps.first { $0.name == name } }
    }

    /// Statut global : échec si une étape non ignorée a échoué ; succès si tout est OK.
    var overall: StepStatus {
        if steps.contains(where: { $0.status == .running }) { return .running }
        if steps.contains(where: { $0.status == .failure }) { return .failure }
        if steps.allSatisfy({ $0.status == .pending }) { return .pending }
        if steps.contains(where: { $0.status == .success }) { return .success }
        return .pending
    }

    var successCount: Int { steps.filter { $0.status == .success }.count }
}
