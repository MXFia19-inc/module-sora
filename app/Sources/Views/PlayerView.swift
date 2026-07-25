import SwiftUI
import UIKit
import AVKit
import AVFoundation

/// Lecteur natif : AVPlayer avec en-têtes HTTP par flux + export vers apps tierces.
struct PlayerView: View {
    let stream: StreamResult
    let subtitles: [SubtitleTrack]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var debugLog: DebugLog

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AVPlayerContainer(stream: stream) { kind, message, detail in
                debugLog.append(kind, message, module: "Player", detail: detail)
            }
            .ignoresSafeArea()

            HStack(spacing: 16) {
                Menu {
                    ForEach(ExternalPlayer.allCases) { player in
                        if let url = player.url(for: stream.url) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Label("\(L("Open in")) \(player.name)", systemImage: "arrow.up.forward.app")
                            }
                        }
                    }
                    Button {
                        UIPasteboard.general.string = stream.url
                    } label: { Label(L("Copy the stream URL"), systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if !subtitles.isEmpty {
                Text("\(subtitles.count) \(L("subtitle track(s) — not muxed by the native player; use export."))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

/// Enveloppe AVPlayerViewController avec en-têtes HTTP personnalisés,
/// instrumentée : statut de lecture, stalls, buffer et erreurs sont journalisés.
private struct AVPlayerContainer: UIViewControllerRepresentable {
    let stream: StreamResult
    let log: (LogKind, String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(log: log) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let controller = AVPlayerViewController()
        guard let url = URL(string: stream.url) else {
            log(.error, "Invalid stream URL", stream.url)
            return controller
        }

        var options: [String: Any] = [:]
        if !stream.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
        }
        log(.player, "▶︎ \(stream.isHLS ? "HLS" : "MP4") · \(stream.title)", stream.url)
        if !stream.headers.isEmpty {
            let list = stream.headers.map { "\($0.key): \($0.value)" }.joined(separator: " · ")
            log(.player, "Headers (\(stream.headers.count))", list)
        }

        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true

        context.coordinator.observe(player: player, item: item)

        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        controller.player = nil
        coordinator.stop()
    }

    /// Observe l'état du lecteur et journalise les événements utiles au debug.
    final class Coordinator {
        private let log: (LogKind, String, String?) -> Void
        private var observations: [NSKeyValueObservation] = []
        private var tokens: [NSObjectProtocol] = []

        init(log: @escaping (LogKind, String, String?) -> Void) { self.log = log }

        func observe(player: AVPlayer, item: AVPlayerItem) {
            observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
                switch item.status {
                case .readyToPlay:
                    self?.log(.player, "Item status: readyToPlay", nil)
                case .failed:
                    let msg = item.error?.localizedDescription ?? "unknown error"
                    self?.log(.error, "Item status: failed — \(msg)", nil)
                default:
                    self?.log(.player, "Item status: unknown", nil)
                }
            })

            observations.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                if item.isPlaybackBufferEmpty { self?.log(.player, "Buffer empty — rebuffering", nil) }
            })

            observations.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                if item.isPlaybackLikelyToKeepUp { self?.log(.player, "Buffer ready — playback likely to keep up", nil) }
            })

            observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                switch player.timeControlStatus {
                case .playing: self?.log(.player, "Playing", nil)
                case .paused: self?.log(.player, "Paused", nil)
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    self?.log(.player, "Waiting — \(reason)", nil)
                @unknown default: break
                }
            })

            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: .AVPlayerItemPlaybackStalled,
                                             object: item, queue: .main) { [weak self] _ in
                self?.log(.error, "Playback stalled", nil)
            })
            tokens.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                             object: item, queue: .main) { [weak self] note in
                let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.log(.error, "Failed to play to end — \(err?.localizedDescription ?? "unknown")", nil)
            })
            tokens.append(center.addObserver(forName: .AVPlayerItemNewErrorLogEntry,
                                             object: item, queue: .main) { [weak self] _ in
                guard let last = item.errorLog()?.events.last else { return }
                self?.log(.error,
                          "Error log: \(last.errorComment ?? "—") (status \(last.errorStatusCode))",
                          last.uri)
            })
            tokens.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: item, queue: .main) { [weak self] _ in
                self?.log(.player, "Playback finished", nil)
            })
        }

        func stop() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
        }

        deinit { stop() }
    }
}

/// Lecteurs tiers cibles pour l'export.
private enum ExternalPlayer: String, CaseIterable, Identifiable {
    case vlc, infuse, outplayer
    var id: String { rawValue }

    var name: String {
        switch self {
        case .vlc: return "VLC"
        case .infuse: return "Infuse"
        case .outplayer: return "Outplayer"
        }
    }

    func url(for streamURL: String) -> URL? {
        guard let encoded = streamURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        switch self {
        case .vlc:
            return URL(string: "vlc://\(streamURL)")
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        case .outplayer:
            return URL(string: "outplayer://\(streamURL)")
        }
    }
}
