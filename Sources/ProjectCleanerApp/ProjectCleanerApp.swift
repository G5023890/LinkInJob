import AppKit
import SwiftUI

@main
struct ProjectCleanerDesktopApp: App {
    @StateObject private var viewModel = CleanerViewModel()

    var body: some Scene {
        WindowGroup {
            ProjectCleanerView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            ProjectCleanerCommands(viewModel: viewModel)
        }
    }
}

struct ProjectCleanerCommands: Commands {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some Commands {
        CommandMenu("Project Cleaner") {
            Button("About Project Cleaner") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Divider()

            Button("Rescan") {
                viewModel.rescan()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isBusy)

            Divider()

            Button("Quit Project Cleaner") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
