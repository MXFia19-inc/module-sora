import SwiftUI

@main
struct ModuleTesterApp: App {
    @StateObject private var moduleStore = ModuleStore()
    @StateObject private var debugLog = DebugLog()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(moduleStore)
                .environmentObject(debugLog)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
