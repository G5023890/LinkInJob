import AppKit
import SwiftUI

struct ApplicationListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var isSearchFocused: Bool
    @FocusState private var listFocused: Bool

    var body: some View {
        List(selection: $viewModel.selectedItemID) {
            ForEach(viewModel.filteredApplications) { item in
                ApplicationRowView(item: item) {
                    viewModel.toggleStar(for: item)
                }
                .tag(item.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedItemID = item.id
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if item.jobURL != nil {
                        viewModel.openJobLink(for: item)
                    } else {
                        viewModel.openSourceFile(for: item)
                    }
                })
                .contextMenu {
                    Menu("Set Stage") {
                        ForEach(Stage.allCases, id: \.self) { stage in
                            Button(stage.title) {
                                viewModel.setStage(stage, for: item)
                            }
                        }
                    }

                    if item.jobURL != nil {
                        Button("Open Job Link") {
                            viewModel.openJobLink(for: item)
                        }
                    }

                    Button("Open Source File") {
                        viewModel.openSourceFile(for: item)
                    }

                    Button(item.starred ? "Unstar" : "Toggle Star") {
                        viewModel.toggleStar(for: item)
                    }

                    Button("Reset to Auto") {
                        viewModel.resetToAuto(for: item)
                    }
                }
            }
        }
        .listStyle(.inset)
        .focused($listFocused)
        .background(
            KeyCaptureView(isEnabled: listFocused && !isSearchFocused) { event in
                guard let item = viewModel.selectedItem else { return }
                switch event {
                case .letter(let char):
                    viewModel.handleListHotkey(String(char))
                case .returnKey:
                    if item.jobURL != nil {
                        viewModel.openJobLink(for: item)
                    } else {
                        viewModel.openSourceFile(for: item)
                    }
                case .space:
                    viewModel.openSourceFile(for: item)
                }
            }
        )
        .navigationTitle("Applications")
        .onAppear {
            listFocused = true
        }
    }
}

private enum KeyAction {
    case letter(Character)
    case returnKey
    case space
}

private struct KeyCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyAction: (KeyAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyAction: onKeyAction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onKeyAction = onKeyAction
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled = false
        var onKeyAction: (KeyAction) -> Void
        private var monitor: Any?

        init(onKeyAction: @escaping (KeyAction) -> Void) {
            self.onKeyAction = onKeyAction
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
                    return event
                }

                switch event.keyCode {
                case 36:
                    self.onKeyAction(.returnKey)
                    return nil
                case 49:
                    self.onKeyAction(.space)
                    return nil
                default:
                    if let char = event.charactersIgnoringModifiers?.lowercased().first,
                       ["i", "r", "a", "s", "f"].contains(char) {
                        self.onKeyAction(.letter(char))
                        return nil
                    }
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
