import SwiftUI

/// Détails d'un média + liste des épisodes.
struct DetailView: View {
    let runner: ModuleRunner?
    let item: SearchItem

    @State private var detail: MediaDetail?
    @State private var episodes: [EpisodeLink] = []
    @State private var detailRaw = ""
    @State private var episodesRaw = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: item.image, cornerRadius: 10)
                        .frame(width: 90, height: 135)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline)
                        if let detail {
                            if detail.aliases != "N/A" {
                                Text(detail.aliases).font(.caption).foregroundStyle(.secondary)
                            }
                            if detail.airdate != "N/A" {
                                Text(detail.airdate).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(item.href).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                }
            }

            if let detail, detail.description != "N/A" {
                Section("Synopsis") {
                    Text(detail.description).font(.callout)
                }
            }

            if let errorMessage {
                Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
            }

            Section("Épisodes (\(episodes.count))") {
                ForEach(episodes) { ep in
                    NavigationLink {
                        StreamPickerView(runner: runner, episode: ep)
                    } label: {
                        EpisodeRow(episode: ep)
                    }
                }
            }
        }
        .navigationTitle("Détails")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    RawJSONInlineButton(title: "extractDetails", raw: detailRaw)
                    RawJSONInlineButton(title: "extractEpisodes", raw: episodesRaw)
                } label: {
                    Image(systemName: "curlybraces")
                }
                .disabled(detailRaw.isEmpty && episodesRaw.isEmpty)
            }
        }
        .overlay {
            if isLoading { ProgressView().controlSize(.large) }
        }
        .task { await load() }
    }

    private func load() async {
        guard let runner, detail == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let d = runner.details(item.href)
            async let e = runner.episodes(item.href)
            let (dr, er) = try await (d, e)
            detail = dr.value
            detailRaw = dr.raw
            episodes = er.value
            episodesRaw = er.raw
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct EpisodeRow: View {
    let episode: EpisodeLink

    var body: some View {
        HStack(spacing: 10) {
            if let image = episode.image {
                RemoteImage(url: image, cornerRadius: 6)
                    .frame(width: 60, height: 34)
            }
            Text(episode.displayTitle)
            Spacer()
            Image(systemName: "play.circle").foregroundStyle(.secondary)
        }
    }
}

/// Ouvre le JSON brut depuis un menu (présente une feuille).
private struct RawJSONInlineButton: View {
    let title: String
    let raw: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("JSON : \(title)", systemImage: "curlybraces")
        }
        .disabled(raw.isEmpty)
        .sheet(isPresented: $showing) { RawJSONView(title: title, raw: raw) }
    }
}
