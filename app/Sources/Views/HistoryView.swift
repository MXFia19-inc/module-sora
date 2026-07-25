import SwiftUI
import UIKit

/// Historique des lancements de test, avec comparaison au lancement précédent.
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if history.runs.isEmpty {
                    ContentUnavailableViewCompat(
                        title: L("No run yet"),
                        systemImage: "clock.arrow.circlepath",
                        description: L("Mass test runs are recorded here so you can compare them.")
                    )
                }
                ForEach(history.runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        RunRow(run: run, diff: history.diff(for: run))
                    }
                    .swipeActions {
                        Button(role: .destructive) { history.remove(run) } label: {
                            Label(L("Delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(L("History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("Close")) { dismiss() } }
                if !history.runs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { history.clear() } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct RunRow: View {
    let run: TestRunRecord
    let diff: RunDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Spacer()
                Text(run.summary)
                    .font(.caption).bold()
                    .foregroundStyle(run.okCount == run.total ? .green : .orange)
            }
            HStack(spacing: 8) {
                Text(run.source).font(.caption2).foregroundStyle(.tertiary)
                if let diff {
                    if !diff.regressions.isEmpty {
                        Label("\(diff.regressions.count)", systemImage: "arrow.down.right")
                            .font(.caption2).foregroundStyle(.red)
                    }
                    if !diff.fixes.isEmpty {
                        Label("\(diff.fixes.count)", systemImage: "arrow.up.right")
                            .font(.caption2).foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Détail d'un lancement : modules et différences avec le précédent.
private struct RunDetailView: View {
    let run: TestRunRecord
    @EnvironmentObject private var history: HistoryStore

    private var diff: RunDiff? { history.diff(for: run) }

    var body: some View {
        List {
            Section {
                LabeledContent(L("Date"), value: run.date.formatted())
                LabeledContent(L("Source"), value: run.source)
                LabeledContent(L("Result"), value: "\(run.summary) OK")
            }

            if let diff, !diff.isEmpty {
                Section(L("Changes since previous run")) {
                    ForEach(diff.regressions, id: \.self) { item in
                        Label(item, systemImage: "arrow.down.right.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                    ForEach(diff.fixes, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    ForEach(diff.added, id: \.self) { item in
                        Label("\(item) (\(L("new")))", systemImage: "plus.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(diff.removed, id: \.self) { item in
                        Label("\(item) (\(L("removed")))", systemImage: "minus.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("\(L("Modules")) (\(run.modules.count))") {
                ForEach(run.modules, id: \.moduleName) { module in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: statusIcon(module.overall))
                                .foregroundStyle(statusColor(module.overall))
                            Text(module.moduleName).font(.subheadline)
                            Spacer()
                            Text("\(module.successCount)/\(module.stepCount)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(L(module.category)) · « \(module.keyword) »")
                            .font(.caption2).foregroundStyle(.tertiary)
                        HStack(spacing: 8) {
                            ForEach(ModuleTestReport.stepNames, id: \.self) { step in
                                if let raw = module.steps[step] {
                                    VStack(spacing: 1) {
                                        Image(systemName: statusIcon(raw))
                                            .font(.system(size: 9))
                                            .foregroundStyle(statusColor(raw))
                                        Text(String(L(step).prefix(4)))
                                            .font(.system(size: 7))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(run.summary)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusIcon(_ raw: String) -> String {
        (StepStatus(rawValue: raw) ?? .pending).icon
    }

    private func statusColor(_ raw: String) -> Color {
        (StepStatus(rawValue: raw) ?? .pending).color
    }
}
