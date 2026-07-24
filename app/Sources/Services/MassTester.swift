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
    /// `customKeywords` : mot-clé libre par id de module (prioritaire s'il est non vide).
    func run(modules: [LoadedModule], overrides: [String: TestCategory],
             customKeywords: [String: String] = [:],
             debugLog: DebugLog, settings: AppSettings) async {
        guard !isRunning else { return }
        reports = modules.map { module in
            let category = overrides[module.id] ?? TestCategory.from(type: module.manifest.type)
            let custom = customKeywords[module.id]?.trimmingCharacters(in: .whitespaces) ?? ""
            let keyword = custom.isEmpty ? settings.keyword(for: category) : custom
            return ModuleTestReport(module: module, category: category, keyword: keyword)
        }
        isRunning = true
        for index in reports.indices {
            currentIndex = index
            await runOne(index: index, debugLog: debugLog, settings: settings)
        }
        currentIndex = nil
        isRunning = false
    }

    /// Relance un seul module (réinitialise ses étapes) sans toucher aux autres.
    /// `keyword` permet de relancer avec un mot-clé différent.
    func runSingle(reportId: String, keyword: String? = nil,
                   debugLog: DebugLog, settings: AppSettings) async {
        guard !isRunning, let index = reports.firstIndex(where: { $0.id == reportId }) else { return }
        isRunning = true
        let old = reports[index]
        let newKeyword = (keyword?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? old.keyword
        reports[index] = ModuleTestReport(module: old.module, category: old.category, keyword: newKeyword)
        currentIndex = index
        await runOne(index: index, debugLog: debugLog, settings: settings)
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
            runnerOpt = try await timed(index, "Loading") {
                try ModuleRunner(module: self.reports[index].module, debugLog: debugLog, settings: settings)
            }
        } catch {
            fail(index, "Loading", error)
            skipFrom(index, "Search")
            return
        }
        guard let runner = runnerOpt else { return }
        success(index, "Loading", "module loaded")

        // 2. Recherche.
        var firstHref: String?
        do {
            let result = try await timed(index, "Search") { try await runner.search(keyword) }
            setRaw(index, "Search", result.raw)
            if let first = result.value.first {
                firstHref = first.href
                success(index, "Search", "\(result.value.count) result(s) · « \(first.title) »")
            } else {
                fail(index, "Search", message: "0 result for « \(keyword) »")
            }
        } catch {
            fail(index, "Search", error)
        }

        guard let href = firstHref else {
            skip(index, "Details"); skip(index, "Episodes"); skip(index, "Streams")
            return
        }

        // 3. Détails.
        do {
            let result = try await timed(index, "Details") { try await runner.details(href) }
            setRaw(index, "Details", result.raw)
            let d = result.value
            let hasContent = d.description != "N/A" || d.aliases != "N/A" || d.airdate != "N/A"
            if hasContent {
                success(index, "Details", d.description == "N/A" ? d.aliases : String(d.description.prefix(60)))
            } else {
                fail(index, "Details", message: "all fields N/A")
            }
        } catch {
            fail(index, "Details", error)
        }

        // 4. Épisodes.
        var targetEpisode: EpisodeLink?
        let category = reports[index].category
        do {
            let result = try await timed(index, "Episodes") { try await runner.episodes(href) }
            setRaw(index, "Episodes", result.raw)
            if !result.value.isEmpty {
                targetEpisode = pickEpisode(result.value, category: category,
                                            serieEpisode: settings.serieEpisode)
                var detail = "\(result.value.count) episode(s)"
                if category == .serie, let ep = targetEpisode {
                    detail += " · test ep. \(Int(ep.number) == 0 ? settings.serieEpisode : Int(ep.number))"
                }
                success(index, "Episodes", detail)
            } else {
                fail(index, "Episodes", message: "0 episode")
            }
        } catch {
            fail(index, "Episodes", error)
        }

        guard let episodeHref = targetEpisode?.href else {
            skip(index, "Streams")
            return
        }

        // 5. Flux.
        do {
            let result = try await timed(index, "Streams") { try await runner.streams(episodeHref) }
            setRaw(index, "Streams", result.raw)
            if let first = result.value.streams.first {
                success(index, "Streams", "\(result.value.streams.count) stream(s) · « \(first.title) »")
            } else {
                fail(index, "Streams", message: "0 playable stream")
            }
        } catch {
            fail(index, "Streams", error)
        }
    }

    /// Nombre de modules dont le test est un succès complet.
    var okCount: Int { reports.filter { $0.overall == .success }.count }

    /// Rapport texte exportable (copier / partager).
    func reportText() -> String {
        var out = "Test report — \(okCount)/\(reports.count) module(s) OK\n"
        out += "\(Date().formatted())\n\n"
        for r in reports {
            out += "• \(r.module.name)  [\(r.category.label)] · keyword « \(r.keyword) »  → \(symbol(r.overall))\n"
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

    /// Rapport structuré en JSON (export fichier).
    func reportJSON() -> String {
        let arr: [[String: Any]] = reports.map { r in
            var steps: [[String: Any]] = []
            for s in r.steps {
                var step: [String: Any] = ["name": s.name, "status": s.status.rawValue]
                if let ms = s.durationMs { step["durationMs"] = ms }
                if let d = s.detail { step["detail"] = d }
                if let raw = s.raw { step["raw"] = raw }
                steps.append(step)
            }
            return [
                "module": r.module.name,
                "category": r.category.label,
                "keyword": r.keyword,
                "overall": r.overall.rawValue,
                "steps": steps,
            ]
        }
        let root: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "okCount": okCount,
            "total": reports.count,
            "reports": arr,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
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

    private func setRaw(_ index: Int, _ step: String, _ raw: String) {
        guard let i = reports[index].steps.firstIndex(where: { $0.name == step }) else { return }
        reports[index].steps[i].raw = raw
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
        update(index, step, .skipped, "ignored")
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
