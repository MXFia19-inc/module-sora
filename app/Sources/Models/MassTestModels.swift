import SwiftUI

/// Catégorie de test déduite du champ `type` d'un module.
enum TestCategory: String, CaseIterable, Identifiable {
    case anime, film, serie, manga
    var id: String { rawValue }

    /// Libellé anglais (clé de traduction).
    var label: String {
        switch self {
        case .anime: return "Anime"
        case .film: return "Movie"
        case .serie: return "Series"
        case .manga: return "Manga"
        }
    }

    /// Déduit la catégorie principale depuis le `type` (priorité manga > anime > film > série).
    static func from(type: String?) -> TestCategory {
        categories(from: type).first ?? .anime
    }

    /// Toutes les catégories déclarées par le `type` (ex. "anime/shows/movies"
    /// → [anime, film, série]). Ordre = priorité manga > anime > film > série.
    static func categories(from type: String?) -> [TestCategory] {
        let t = (type ?? "").lowercased()
        var result: [TestCategory] = []
        if t.contains("manga") || t.contains("scan") { result.append(.manga) }
        if t.contains("anime") { result.append(.anime) }
        if t.contains("movie") || t.contains("film") { result.append(.film) }
        if t.contains("show") || t.contains("serie") || t.contains("série") || t.contains("tv") { result.append(.serie) }
        return result.isEmpty ? [.anime] : result
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
    /// JSON brut renvoyé par la fonction du module pour cette étape.
    var raw: String?
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

    /// Noms d'étapes (identifiants stables en anglais ; traduits à l'affichage).
    static let stepNames = ["Loading", "Search", "Details", "Episodes", "Streams"]

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
