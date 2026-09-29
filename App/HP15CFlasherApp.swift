import AppKit
import SwiftUI

@main
struct HP15CFlasherApp: App {
    @StateObject private var store = FlasherStore()

    var body: some Scene {
        Window("15CE Flasher", id: "flasher-main") {
            ContentView()
                .environmentObject(store)
                .navigationTitle(store.appTitle)
                .onAppear { store.start() }
                .onDisappear { store.stop() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 760)
        #if DEBUG
        .commands {
            DebugCommands()
        }
        #endif

        #if DEBUG
        Window("Pogo Wing Editor", id: "pogo-wing-editor") {
            PogoWingEditorView()
        }
        .windowResizability(.contentSize)
        #endif
    }
}

#if DEBUG
private struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Pogo Wing Editor") {
                openWindow(id: "pogo-wing-editor")
            }
            Button("Open HTML Wing Tracer…") {
                let root = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let html = root.appendingPathComponent("scripts/trace-pogo-wings.html")
                NSWorkspace.shared.open(html)
            }
        }
    }
}
#endif
