import SwiftUI

/// Liste des flux d'un épisode → lecture.
struct StreamPickerView: View {
    let runner: ModuleRunner?
    let episode: EpisodeLink

    @State private var extraction: StreamExtraction?
    @State private var raw = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playing: StreamResult?
    @State private var jsonSheet: RawJSONPayload?

    var body: some View {
        List {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
            }

            if let extraction {
                Section("\(L("Streams")) (\(extraction.streams.count))") {
                    if extraction.streams.isEmpty {
                        Text(L("No stream returned.")).foregroundStyle(.secondary)
                    }
                    ForEach(extraction.streams) { stream in
                        StreamRow(stream: stream) { playing = stream }
                    }
                }

                if !extraction.subtitles.isEmpty {
                    Section("\(L("Subtitles")) (\(extraction.subtitles.count))") {
                        ForEach(extraction.subtitles) { sub in
                            Label(sub.label, systemImage: "captions.bubble")
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle(episode.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    jsonSheet = RawJSONPayload(title: "extractStreamUrl", raw: raw)
                } label: { Image(systemName: "curlybraces") }
                    .disabled(raw.isEmpty)
            }
        }
        .sheet(item: $jsonSheet) { payload in
            RawJSONView(title: payload.title, raw: payload.raw)
        }
        .overlay {
            if isLoading { ProgressView().controlSize(.large) }
        }
        .fullScreenCover(item: $playing) { stream in
            PlayerView(stream: stream, subtitles: extraction?.subtitles ?? [])
        }
        .task { await load() }
    }

    private func load() async {
        guard let runner, extraction == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            let r = try await runner.streams(episode.href)
            extraction = r.value
            raw = r.raw
            if r.value.streams.isEmpty {
                errorMessage = L("extractStreamUrl responded, but with no playable stream.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct StreamRow: View {
    let stream: StreamResult
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.title).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(stream.isHLS ? "HLS" : "MP4")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.secondary.opacity(0.2), in: Capsule())
                        if !stream.headers.isEmpty {
                            Text("\(stream.headers.count) \(L("headers"))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}
