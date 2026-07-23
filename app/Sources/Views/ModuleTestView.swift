import SwiftUI

/// Session de test d'un module : détient le `ModuleRunner` (contexte JS vivant)
/// et l'état de recherche. Le runner est construit lors de `attach(...)` car il
/// dépend de l'environnement (logs, réglages).
@MainActor
final class TestSession: ObservableObject {
    let module: LoadedModule
    @Published var query = ""
    @Published var results: [SearchItem] = []
    @Published var lastRaw = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private(set) var runner: ModuleRunner?
    private var initError: String?

    init(module: LoadedModule) {
        self.module = module
    }

    /// Construit le runner (idempotent).
    func attach(debugLog: DebugLog, settings: AppSettings) {
        guard runner == nil, initError == nil else { return }
        do {
            runner = try ModuleRunner(module: module, debugLog: debugLog, settings: settings)
        } catch {
            initError = error.localizedDescription
            errorMessage = initError
        }
    }

    func search() async {
        guard let runner else { errorMessage = initError ?? "Module non chargé."; return }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let r = try await runner.search(keyword)
            results = r.value
            lastRaw = r.raw
            if results.isEmpty { errorMessage = "Aucun résultat (le module a répondu, mais vide)." }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Recherche dans un module → grille de résultats.
struct ModuleTestView: View {
    let module: LoadedModule
    @EnvironmentObject private var debugLog: DebugLog
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var session: TestSession
    @State private var jsonSheet: RawJSONPayload?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(module: LoadedModule) {
        self.module = module
        _session = StateObject(wrappedValue: TestSession(module: module))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = session.errorMessage {
                ErrorBanner(message: error).padding(.top, 8)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(session.results) { item in
                        NavigationLink {
                            DetailView(runner: session.runner, item: item)
                        } label: {
                            ResultCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $session.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Rechercher dans \(module.name)"
        )
        .keyboardDoneToolbar()
        .onSubmit(of: .search) { Task { await session.search() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    jsonSheet = RawJSONPayload(title: "searchResults", raw: session.lastRaw)
                } label: { Image(systemName: "curlybraces") }
                    .disabled(session.lastRaw.isEmpty)
            }
        }
        .sheet(item: $jsonSheet) { payload in
            RawJSONView(title: payload.title, raw: payload.raw)
        }
        .overlay {
            if session.isLoading { ProgressView().controlSize(.large) }
        }
        .task {
            session.attach(debugLog: debugLog, settings: settings)
        }
    }
}

private struct ResultCell: View {
    let item: SearchItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.image, cornerRadius: 10)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
