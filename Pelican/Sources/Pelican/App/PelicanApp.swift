import AppKit
import SwiftUI

@main
struct PelicanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        Window("Pelican", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.interaction)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .commands {
            PelicanCommands(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.installKeyMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct PelicanCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan Folder…") { model.chooseFolder() }
                .keyboardShortcut("o")
            Button("Rescan") { model.rescan() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.tree == nil || model.phase == .scanning)
            Button("Stop Scan") { model.cancelScan() }
                .keyboardShortcut(".")
                .disabled(model.phase != .scanning)
        }

        CommandMenu("Item") {
            Button("Quick Look") { if let id = model.actionTarget { model.quickLook(id) } }
                .keyboardShortcut("y")
            Button("Reveal in Finder") { if let id = model.actionTarget { model.reveal(id) } }
                .keyboardShortcut("r")
            Divider()
            Button("Add to Purge Basket") { if let id = model.actionTarget { model.toggleBasket(id) } }
                .keyboardShortcut("b")
            Button("Move Purge Basket to Trash") { model.trashBasket() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.basket.isEmpty)
            Divider()
            Button("Move to Trash") { if let id = model.actionTarget { model.requestTrash([id]) } }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("Delete Permanently…") { if let id = model.actionTarget { model.requestPermanentDelete([id]) } }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
        }

        CommandMenu("Navigate") {
            Button("Enclosing Folder") { model.zoomOut() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Zoom In") { model.zoomIntoTarget() }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button("Sunburst") { model.vizMode = .sunburst }
                .keyboardShortcut("1")
            Button("Treemap") { model.vizMode = .treemap }
                .keyboardShortcut("2")
        }
    }
}
