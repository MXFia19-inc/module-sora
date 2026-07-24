import SwiftUI

@main
struct ModuleTesterApp: App {
    @StateObject private var moduleStore = ModuleStore()
    @StateObject private var debugLog = DebugLog()
    @StateObject private var settings = AppSettings()
    @StateObject private var massTester = MassTester()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(moduleStore)
                .environmentObject(debugLog)
                .environmentObject(settings)
                .environmentObject(massTester)
                .preferredColorScheme(.dark)
                .id(settings.language)
        }
    }
}
