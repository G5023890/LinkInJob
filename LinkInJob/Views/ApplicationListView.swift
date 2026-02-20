import AppKit
import SwiftUI

struct ApplicationListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            List(selection: $viewModel.selectedItemID) {
                ForEach(viewModel.filteredApplications) { item in
                    ApplicationRowView(
                        item: item,
                        isSelected: viewModel.selectedItemID == item.id,
                        toggleStar: { viewModel.toggleStar(for: item) }
                    )
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
                    .onTapGesture(count: 2) {
                        viewModel.selectedItemID = item.id
                        if item.jobURL != nil {
                            viewModel.openJobLink(for: item)
                        } else {
                            viewModel.openSourceFile(for: item)
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .listRowSeparator(.hidden)
                    .tag(item.id)
                }
            }
            .listStyle(.plain)
            .focused($listFocused)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(
                KeyCaptureView(isEnabled: listFocused && !searchFocused) { event in
                    switch event {
                    case .letter(let char):
                        viewModel.handleListHotkey(String(char))
                    case .returnKey:
                        guard let item = viewModel.selectedItem else { return }
                        if item.jobURL != nil {
                            viewModel.openJobLink(for: item)
                        } else {
                            viewModel.openSourceFile(for: item)
                        }
                    case .space:
                        guard let item = viewModel.selectedItem else { return }
                        viewModel.openSourceFile(for: item)
                    case .arrowUp:
                        viewModel.moveSelectionInFilteredList(by: -1)
                    case .arrowDown:
                        viewModel.moveSelectionInFilteredList(by: 1)
                    }
                }
            )
        }
        .navigationTitle("Applications")
        .onAppear {
            listFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("Sort", selection: $viewModel.sortOption) {
                ForEach(AppViewModel.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)

            TextField("Search company, role, location", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .frame(maxWidth: 430, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Button("Focus Search") {
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }
}

private enum KeyAction {
    case letter(Character)
    case returnKey
    case space
    case arrowUp
    case arrowDown
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
                case 126:
                    self.onKeyAction(.arrowUp)
                    return nil
                case 125:
                    self.onKeyAction(.arrowDown)
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
