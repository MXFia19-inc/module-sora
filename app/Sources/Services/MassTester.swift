import Foundation

/// Exécute un test en masse : pour chaque module sélectionné, déroule le
/// pipeline Chargement → Recherche → Détails → Épisodes → Flux avec le mot-clé
/// correspondant à son type, et publie le statut de chaque étape.
@MainActor
final class MassTester: ObservableObject {
    @Published private(set) var reports: [ModuleTestReport] = []
    @Published private(set) var isRunning = false
    @Published private(set) var currentIndex: Int?

    /// `overrides` : catégorie choisie manuellement par id de module (sinon Auto).
    func run(modules: [LoadedModule], overrides: [String: TestCategory],
             debugLog: DebugLog, settings: AppSettings) async {
        guard !isRunning else { return }
        reports = modules.map { module in
            let category = overrides[module.id] ?? TestCategory.from(type: module.manifest.type)
            return ModuleTestReport(module: module, category: category,
                                    keyword: settings.keyword(for: category))
        }
        isRunning = true
        for index in reports.indices {
            currentIndex = index
            await runOne(index: index, debugLog: debugLog, settings: settings)
        }
        currentIndex = nil
        isRunning = false
    }

    // MARK: - Pipeline

    private func runOne(index: Int, debugLog: DebugLog, settings: AppSettings) async {
        reports[index].startedAt = Date()
        let keyword = reports[index].keyword

        // Coupe l'activité de fond du module quand le test est fini (timers, ping…).
        var runnerOpt: ModuleRunner?
        defer { runnerOpt?.dispose() }

        // 1. Chargement (évaluation du script).
        do {
            runnerOpt = try await timed(index, "Chargement") {
                try ModuleRunner(module: self.reports[index].module, debugLog: debugLog, settings: settings)
            }
        } catch {
            fail(index, "Chargement", error)
            skipFrom(index, "Recherche")
            return
        }
        guard let runner = runnerOpt else { return }
        success(index, "Chargement", "module chargé")

        // 2. Recherche.
        var firstHref: String?
        do {
            let result = try await timed(index, "Recherche") { try await runner.search(keyword) }
            if let first = result.value.first {
                firstHref = first.href
                success(index, "Recherche", "\(result.value.count) résultat(s) · « \(first.title) »")
            } else {
                fail(index, "Recherche", message: "0 résultat pour « \(keyword) »")
            }
        } catch {
            fail(index, "Recherche", error)
        }

        guard let href = firstHref else {
            skip(index, "Détails"); skip(index, "Épisodes"); skip(index, "Flux")
            return
        }

        // 3. Détails.
        do {
            let result = try await timed(index, "Détails") { try await runner.details(href) }
            let d = result.value
            let hasContent = d.description != "N/A" || d.aliases != "N/A" || d.airdate != "N/A"
            if hasContent {
                success(index, "Détails", d.description == "N/A" ? d.aliases : String(d.description.prefix(60)))
            } else {
                fail(index, "Détails", message: "tous les champs à N/A")
            }
        } catch {
            fail(index, "Détails", error)
        }

        // 4. Épisodes.
        var targetEpisode: EpisodeLink?
        let category = reports[index].category
        do {
            let result = try await timed(index, "Épisodes") { try await runner.episodes(href) }
            if !result.value.isEmpty {
                targetEpisode = pickEpisode(result.value, category: category,
                                            serieEpisode: settings.serieEpisode)
                var detail = "\(result.value.count) épisode(s)"
                if category == .serie, let ep = targetEpisode {
                    detail += " · test ép. \(Int(ep.number) == 0 ? settings.serieEpisode : Int(ep.number))"
                }
                success(index, "Épisodes", detail)
            } else {
                fail(index, "Épisodes", message: "0 épisode")
            }
        } catch {
            fail(index, "Épisodes", error)
        }

        guard let episodeHref = targetEpisode?.href else {
            skip(index, "Flux")
            return
        }

        // 5. Flux.
        do {
            let result = try await timed(index, "Flux") { try await runner.streams(episodeHref) }
            if let first = result.value.streams.first {
                success(index, "Flux", "\(result.value.streams.count) flux · « \(first.title) »")
            } else {
                fail(index, "Flux", message: "0 flux jouable")
            }
        } catch {
            fail(index, "Flux", error)
        }
    }

    /// Nombre de modules dont le test est un succès complet.
    var okCount: Int { reports.filter { $0.overall == .success }.count }

    /// Rapport texte exportable (copier / partager).
    func reportText() -> String {
        var out = "Rapport de test — \(okCount)/\(reports.count) module(s) OK\n"
        out += "\(Date().formatted())\n\n"
        for r in reports {
            out += "• \(r.module.name)  [\(r.category.label)] · mot-clé « \(r.keyword) »  → \(symbol(r.overall))\n"
            for s in r.steps {
                out += "    \(symbol(s.status)) \(s.name)"
                if let ms = s.durationMs { out += " (\(ms) ms)" }
                if let d = s.detail { out += " — \(d)" }
                out += "\n"
            }
            out += "\n"
        }
        return out
    }

    private func symbol(_ status: StepStatus) -> String {
        switch status {
        case .success: return "✅"
        case .failure: return "❌"
        case .skipped: return "⊘"
        case .running: return "⏳"
        case .pending: return "•"
        }
    }

    /// Choisit l'épisode à tester : pour les séries, celui portant le numéro
    /// demandé (sinon le N-ième, sinon le 1er) ; sinon le premier.
    private func pickEpisode(_ episodes: [EpisodeLink], category: TestCategory,
                             serieEpisode: Int) -> EpisodeLink? {
        guard category == .serie else { return episodes.first }
        if let match = episodes.first(where: { Int($0.number) == serieEpisode }) { return match }
        if serieEpisode >= 1, serieEpisode <= episodes.count { return episodes[serieEpisode - 1] }
        return episodes.first
    }

    // MARK: - Helpers de statut

    private func timed<T>(_ index: Int, _ step: String, _ work: () async throws -> T) async rethrows -> T {
        setStatus(index, step, .running)
        let start = Date()
        defer { setDuration(index, step, Int(Date().timeIntervalSince(start) * 1000)) }
        return try await work()
    }

    private func setStatus(_ index: Int, _ step: String, _ status: StepStatus) {
        guard let i = reports[index].steps.firstIndex(where: { $0.name == step }) else { return }
        reports[index].steps[i].status = status
    }

    private func setDuration(_ index: Int, _ step: String, _ ms: Int) {
        guard let i = reports[index].steps.firstIndex(where: { $0.name == step }) else { return }
        reports[index].steps[i].durationMs = ms
    }

    private func success(_ index: Int, _ step: String, _ detail: String?) {
        update(index, step, .success, detail)
    }

    private func fail(_ index: Int, _ step: String, message: String) {
        update(index, step, .failure, message)
    }

    private func fail(_ index: Int, _ step: String, _ error: Error) {
        update(index, step, .failure, error.localizedDescription)
    }

    private func skip(_ index: Int, _ step: String) {
        update(index, step, .skipped, "ignoré")
    }

    private func skipFrom(_ index: Int, _ step: String) {
        guard let start = ModuleTestReport.stepNames.firstIndex(of: step) else { return }
        for name in ModuleTestReport.stepNames[start...] { skip(index, name) }
    }

    private func update(_ index: Int, _ step: String, _ status: StepStatus, _ detail: String?) {
        guard let i = reports[index].steps.firstIndex(where: { $0.name == step }) else { return }
        reports[index].steps[i].status = status
        reports[index].steps[i].detail = detail
    }
}
