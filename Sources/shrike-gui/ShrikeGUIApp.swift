import AppKit
import SwiftUI

@main
struct ShrikeGUIApp: App {
    var body: some Scene {
        WindowGroup("Shrike") {
            ContentView()
                .onAppear {
                    // When launched unbundled (`swift run shrike-gui`) the process
                    // starts as a background app; promote it so the window shows
                    // and takes focus. A no-op when launched from Shrike.app.
                    NSApplication.shared.setActivationPolicy(.regular)
                    if #available(macOS 14.0, *) {
                        NSApplication.shared.activate()
                    } else {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        // No AppKit title bar at all — SwiftUI paints every pixel blue and
        // ContentView draws the "Shrike" title itself. Tweaking the real
        // title bar's color doesn't survive AppKit repaints (window moves,
        // focus changes), which is why the imperative route was abandoned.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
