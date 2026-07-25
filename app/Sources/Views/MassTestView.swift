import SwiftUI
import UIKit

/// Testeur en masse : sélection de modules, mots-clés par type, exécution du
/// pipeline pour chacun, avec statut par étape et logs séparés par module.
struct MassTestView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var debugLog: DebugLog
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tester: MassTester
    @EnvironmentObject private var presetStore: PresetStore
    @EnvironmentObject private var history: HistoryStore

    @State private var selected: Set<String> = []
    /// Catégorie choisie manuellement par id de module (absent = Auto).
    @State private var overrides: [String: TestCategory] = [:]
    /// Mot-clé libre par id de module (prioritaire sur celui de la catégorie).
    @State private var customKeywords: [String: String] = [:]
    @State private var sharePayload: SharePayload?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var webhookMessage: String?

    var body: some View {
        Form {
            keywordsSection
            modulesSection
            runSection
            if !tester.reports.isEmpty { resultsSection }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L("Mass test"))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert(L("Discord"), isPresented: .constant(webhookMessage != nil)) {
            Button(L("OK")) { webhookMessage = nil }
        } message: {
            Text(webhookMessage ?? "")
        }
        .alert(L("Save as preset…"), isPresented: $showSavePreset) {
            TextField(L("Preset name"), text: $presetName)
            Button(L("Save")) {
                presetStore.save(name: presetName, moduleIds: selected,
                                 overrides: overrides, customKeywords: customKeywords)
                presetName = ""
            }
            Button(L("Cancel"), role: .cancel) { presetName = "" }
        } message: {
            Text(L("Saves the current selection, forced categories and custom keywords."))
        }
        .onAppear {
            if selected.isEmpty { selected = Set(store.modules.map(\.id)) }
        }
    }

    // MARK: - Sections

    private var keywordsSection: some View {
        Section(L("Keywords by type")) {
            LabeledField(label: L("Anime"), text: $settings.kwAnime)
            LabeledField(label: L("Movie"), text: $settings.kwFilm)
            LabeledField(label: L("Show"), text: $settings.kwSerie)
            LabeledField(label: L("Manga"), text: $settings.kwManga)
            LabeledField(label: L("Custom"), text: $settings.kwCustom)
            Stepper("\(L("Tested episode (series)")): \(settings.serieEpisode)",
                    value: $settings.serieEpisode, in: 1...500)
        }
    }

    /// Mot-clé personnalisé d'un module (vide = mot-clé de sa catégorie).
    private func customKeywordBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { customKeywords[id] ?? "" },
            set: { customKeywords[id] = $0 }
        )
    }

    private func effectiveCategory(_ module: LoadedModule) -> TestCategory {
        overrides[module.id] ?? TestCategory.from(type: module.manifest.type)
    }

    private var modulesSection: some View {
        Section {
            if store.modules.isEmpty {
                Text(L("No module installed.")).foregroundStyle(.secondary)
            }
            ForEach(store.modules) { module in
                let cats = TestCategory.categories(from: module.manifest.type)
                VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button {
                        toggle(module.id)
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(module.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(module.id) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(module.name).foregroundStyle(.primary)
                                Text(L(effectiveCategory(module).label) + (cats.count > 1 ? " · " + L("multi-type") : ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Menu {
                        Button("\(L("Auto")) (\(L(TestCategory.from(type: module.manifest.type).label)))") {
                            overrides[module.id] = nil
                        }
                        ForEach(TestCategory.detectable) { c in
                            Button(L(c.label)) { overrides[module.id] = c }
                        }
                        Divider()
                        Button(L("Custom")) { overrides[module.id] = .custom }
                    } label: {
                        HStack(spacing: 2) {
                            Text(overrides[module.id].map { L($0.label) } ?? L("Auto"))
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.caption)
                    }
                }

                // Mot-clé libre : affiché pour « Custom », sinon en surcharge optionnelle.
                if effectiveCategory(module) == .custom {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2).foregroundStyle(.secondary)
                        TextField(L("Custom keyword"), text: customKeywordBinding(module.id))
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.leading, 28)
                }
                }
            }
        } header: {
            HStack(spacing: 12) {
                Text("\(L("Modules to test")) (\(selected.count))")
                Spacer()
                Menu {
                    if !presetStore.presets.isEmpty {
                        ForEach(presetStore.presets) { preset in
                            Button("\(preset.name) (\(preset.moduleIds.count))") { apply(preset) }
                        }
                        Divider()
                    }
                    Button {
                        presetName = ""
                        showSavePreset = true
                    } label: { Label(L("Save as preset…"), systemImage: "square.and.arrow.down") }
                        .disabled(selected.isEmpty)
                    if !presetStore.presets.isEmpty {
                        Menu {
                            ForEach(presetStore.presets) { preset in
                                Button(preset.name, role: .destructive) { presetStore.remove(preset) }
                            }
                        } label: { Label(L("Delete a preset"), systemImage: "trash") }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "bookmark")
                        Text(L("Presets"))
                    }
                    .font(.caption)
                    .textCase(nil)
                }
                Menu {
                    Button(L("Auto")) { setAllCategories(nil) }
                    ForEach(TestCategory.allCases) { c in
                        Button(L(c.label)) { setAllCategories(c) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(L("Set all"))
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                    .textCase(nil)
                }
                Button(selected.count == store.modules.count ? L("None") : L("All")) {
                    selected = selected.count == store.modules.count ? [] : Set(store.modules.map(\.id))
                }
                .font(.caption)
                .textCase(nil)
            }
        }
    }

    /// Charge un préréglage : sélection, catégories et mots-clés personnalisés.
    /// Les modules du préréglage qui ne sont plus installés sont ignorés.
    private func apply(_ preset: TestPreset) {
        let installed = Set(store.modules.map(\.id))
        selected = Set(preset.moduleIds).intersection(installed)
        overrides = presetStore.categories(of: preset).filter { installed.contains($0.key) }
        customKeywords = preset.customKeywords.filter { installed.contains($0.key) }
    }

    /// Applique une catégorie (ou Auto = nil) à TOUS les modules d'un coup.
    private func setAllCategories(_ category: TestCategory?) {
        if let category {
            for module in store.modules { overrides[module.id] = category }
        } else {
            overrides.removeAll()
        }
    }

    private var runSection: some View {
        Section {
            Button {
                let modules = store.modules.filter { selected.contains($0.id) }
                Task {
                    await tester.run(modules: modules, overrides: overrides,
                                     customKeywords: customKeywords,
                                     debugLog: debugLog, settings: settings)
                    history.record(tester.reports)
                    if settings.autoSendReport, settings.hasWebhook { sendToDiscord() }
                }
            } label: {
                HStack {
                    if tester.isRunning {
                        ProgressView().padding(.trailing, 4)
                        Text(L("Testing…"))
                    } else {
                        Image(systemName: "play.fill")
                        Text("\(L("Run test")) (\(selected.count))")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selected.isEmpty || tester.isRunning)
            .buttonStyle(.borderedProminent)
        }
    }

    private var resultsSection: some View {
        Section(L("Results")) {
            HStack {
                Label("\(tester.okCount)/\(tester.reports.count) \(L("modules OK"))",
                      systemImage: tester.okCount == tester.reports.count
                        ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(tester.okCount == tester.reports.count ? .green : .orange)
                    .font(.subheadline)
                Spacer()
                Menu {
                    Button {
                        UIPasteboard.general.string = tester.reportText()
                    } label: { Label(L("Copy (text)"), systemImage: "doc.on.doc") }
                    Button {
                        exportFile(tester.reportText(), ext: "txt")
                    } label: { Label(L("Share .txt"), systemImage: "doc.text") }
                    Button {
                        exportFile(tester.reportJSON(), ext: "json")
                    } label: { Label(L("Share .json"), systemImage: "curlybraces") }
                    if settings.hasWebhook {
                        Divider()
                        Button {
                            sendToDiscord()
                        } label: { Label(L("Send to Discord"), systemImage: "paperplane") }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
            ForEach(tester.reports) { report in
                NavigationLink {
                    ReportDetailView(reportId: report.id)
                } label: {
                    ReportRow(report: report)
                }
                .contextMenu {
                    Button {
                        Task { await tester.runSingle(reportId: report.id, debugLog: debugLog, settings: settings) }
                    } label: { Label(L("Relaunch this module"), systemImage: "arrow.clockwise") }
                    .disabled(tester.isRunning)
                }
            }
        }
    }

    /// Envoie le résumé au webhook Discord configuré.
    private func sendToDiscord() {
        Task {
            do {
                try await tester.sendReportToDiscord(webhook: settings.discordWebhook)
                webhookMessage = L("Report sent to Discord.")
            } catch {
                webhookMessage = error.localizedDescription
            }
        }
    }

    private func exportFile(_ text: String, ext: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rapport-test-modules.\(ext)")
        try? text.data(using: .utf8)?.write(to: url)
        sharePayload = SharePayload(url: url)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

/// Champ texte avec libellé à gauche.
private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            TextField(L("keyword"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Ligne de résultat : nom + type + pastilles d'étapes.
private struct ReportRow: View {
    let report: ModuleTestReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: report.overall.icon).foregroundStyle(report.overall.color)
                Text(report.module.name).font(.subheadline).bold()
                Spacer()
                Text("\(report.successCount)/\(report.steps.count)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(report.steps) { step in
                    VStack(spacing: 2) {
                        Image(systemName: step.status.icon)
                            .font(.caption)
                            .foregroundStyle(step.status.color)
                        Text(String(L(step.name).prefix(4)))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Détail d'un rapport : étapes + logs du module durant ce test.
private struct ReportDetailView: View {
    let reportId: String
    @EnvironmentObject private var tester: MassTester
    @EnvironmentObject private var debugLog: DebugLog
    @EnvironmentObject private var settings: AppSettings
    @State private var jsonSheet: RawJSONPayload?
    /// Mot-clé éditable pour relancer le module avec une autre recherche.
    @State private var editedKeyword = ""

    private var report: ModuleTestReport? { tester.reports.first { $0.id == reportId } }

    private func logs(_ report: ModuleTestReport) -> [LogEntry] {
        let start = report.startedAt ?? .distantPast
        return debugLog.entries.filter { $0.module == report.module.name && $0.date >= start }
    }

    /// Relance le module avec le mot-clé saisi (ou l'actuel s'il est vide).
    private func relaunch() {
        let keyword = editedKeyword.trimmingCharacters(in: .whitespaces)
        Task {
            await tester.runSingle(reportId: reportId,
                                   keyword: keyword.isEmpty ? nil : keyword,
                                   debugLog: debugLog, settings: settings)
        }
    }

    /// Si le Chargement a échoué avec une erreur de syntaxe localisée (« ligne N »),
    /// extrait les lignes de code autour du point fautif.
    private func syntaxSnippet(_ report: ModuleTestReport) -> (fault: Int, lines: [(Int, String)])? {
        guard let load = report.steps.first(where: { $0.name == "Chargement" }),
              load.status == .failure, let detail = load.detail,
              let range = detail.range(of: #"line (\d+)"#, options: .regularExpression),
              let faultLine = Int(detail[range].filter(\.isNumber)) else { return nil }
        let all = report.module.scriptContent.components(separatedBy: "\n")
        guard faultLine >= 1, faultLine <= all.count else { return nil }
        let start = max(1, faultLine - 3), end = min(all.count, faultLine + 3)
        return (faultLine, (start...end).map { ($0, all[$0 - 1]) })
    }

    var body: some View {
        Group {
            if let report {
                content(report)
            } else {
                Text(L("Report unavailable.")).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $jsonSheet) { payload in
            RawJSONView(title: payload.title, raw: payload.raw)
        }
    }

    @ViewBuilder
    private func content(_ report: ModuleTestReport) -> some View {
        let logs = logs(report)
        let syntaxSnippet = syntaxSnippet(report)
        List {
            Section {
                LabeledContent(L("Type"), value: L(report.category.label))
                HStack {
                    Text(L("Keyword"))
                    Spacer()
                    TextField(L("Keyword"), text: $editedKeyword)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { relaunch() }
                }
                Button {
                    relaunch()
                } label: {
                    Label(L("Relaunch with this keyword"), systemImage: "arrow.clockwise")
                }
                .disabled(tester.isRunning || editedKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section(L("Steps")) {
                ForEach(report.steps) { step in
                    HStack(alignment: .top) {
                        Image(systemName: step.status.icon).foregroundStyle(step.status.color)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(L(step.name))
                                Spacer()
                                if let ms = step.durationMs {
                                    Text("\(ms) ms").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if let detail = step.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(step.status == .failure ? .red : .secondary)
                            }
                            if let raw = step.raw, !raw.isEmpty {
                                Button {
                                    jsonSheet = RawJSONPayload(title: step.name, raw: raw)
                                } label: {
                                    Label(L("See JSON"), systemImage: "curlybraces")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            if let snippet = syntaxSnippet {
                Section("\(L("Code around the error")) (\(L("line")) \(snippet.fault))") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snippet.lines, id: \.0) { lineNo, text in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(lineNo)")
                                    .frame(width: 34, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                Text(text.isEmpty ? " " : text)
                                    .foregroundStyle(lineNo == snippet.fault ? .red : .primary)
                                    .fontWeight(lineNo == snippet.fault ? .bold : .regular)
                            }
                            .font(.system(.caption2, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = snippet.lines
                                .map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                        } label: { Label(L("Copy the snippet"), systemImage: "doc.on.doc") }
                    }
                }
            }

            Section("\(L("Module logs")) (\(logs.count))") {
                if logs.isEmpty {
                    Text(L("No log captured.")).foregroundStyle(.secondary)
                }
                ForEach(logs) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Image(systemName: entry.kind == .error ? "exclamationmark.triangle" : "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(entry.kind == .error ? .red : .secondary)
                            Text(entry.timeString).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(entry.kind == .error ? .red : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = entry.message
                        } label: { Label(L("Copy this log"), systemImage: "doc.on.doc") }
                    }
                }
            }
        }
        .navigationTitle(report.module.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    relaunch()
                } label: {
                    Label(L("Relaunch"), systemImage: "arrow.clockwise")
                }
                .disabled(tester.isRunning)
            }
        }
        .onAppear {
            if editedKeyword.isEmpty { editedKeyword = report.keyword }
        }
    }
}
