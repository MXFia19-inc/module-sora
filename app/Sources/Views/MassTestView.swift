import SwiftUI

/// Testeur en masse : sélection de modules, mots-clés par type, exécution du
/// pipeline pour chacun, avec statut par étape et logs séparés par module.
struct MassTestView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var debugLog: DebugLog
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tester: MassTester

    @State private var selected: Set<String> = []

    var body: some View {
        Form {
            keywordsSection
            modulesSection
            runSection
            if !tester.reports.isEmpty { resultsSection }
        }
        .navigationTitle("Test en masse")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear {
            if selected.isEmpty { selected = Set(store.modules.map(\.id)) }
        }
    }

    // MARK: - Sections

    private var keywordsSection: some View {
        Section("Mots-clés par type") {
            LabeledField(label: "Anime", text: $settings.kwAnime)
            LabeledField(label: "Film", text: $settings.kwFilm)
            LabeledField(label: "Série", text: $settings.kwSerie)
            LabeledField(label: "Manga", text: $settings.kwManga)
        }
    }

    private var modulesSection: some View {
        Section {
            if store.modules.isEmpty {
                Text("Aucun module installé.").foregroundStyle(.secondary)
            }
            ForEach(store.modules) { module in
                Button {
                    toggle(module.id)
                } label: {
                    HStack {
                        Image(systemName: selected.contains(module.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(module.id) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(module.name).foregroundStyle(.primary)
                            Text(TestCategory.from(type: module.manifest.type).label)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        } header: {
            HStack {
                Text("Modules à tester (\(selected.count))")
                Spacer()
                Button(selected.count == store.modules.count ? "Aucun" : "Tous") {
                    selected = selected.count == store.modules.count ? [] : Set(store.modules.map(\.id))
                }
                .font(.caption)
                .textCase(nil)
            }
        }
    }

    private var runSection: some View {
        Section {
            Button {
                let modules = store.modules.filter { selected.contains($0.id) }
                Task { await tester.run(modules: modules, debugLog: debugLog, settings: settings) }
            } label: {
                HStack {
                    if tester.isRunning {
                        ProgressView().padding(.trailing, 4)
                        Text("Test en cours…")
                    } else {
                        Image(systemName: "play.fill")
                        Text("Lancer le test (\(selected.count))")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selected.isEmpty || tester.isRunning)
            .buttonStyle(.borderedProminent)
        }
    }

    private var resultsSection: some View {
        Section("Résultats") {
            ForEach(tester.reports) { report in
                NavigationLink {
                    ReportDetailView(report: report)
                } label: {
                    ReportRow(report: report)
                }
            }
        }
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
            TextField("mot-clé", text: $text)
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
                        Text(String(step.name.prefix(4)))
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
    let report: ModuleTestReport
    @EnvironmentObject private var debugLog: DebugLog

    private var logs: [LogEntry] {
        let start = report.startedAt ?? .distantPast
        return debugLog.entries.filter { $0.module == report.module.name && $0.date >= start }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: report.category.label)
                LabeledContent("Mot-clé", value: report.keyword)
            }

            Section("Étapes") {
                ForEach(report.steps) { step in
                    HStack(alignment: .top) {
                        Image(systemName: step.status.icon).foregroundStyle(step.status.color)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(step.name)
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
                        }
                    }
                }
            }

            Section("Logs du module (\(logs.count))") {
                if logs.isEmpty {
                    Text("Aucun log capturé.").foregroundStyle(.secondary)
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
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(report.module.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
