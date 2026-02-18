import AppKit
import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isSearchFocused = false

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            ApplicationListView(isSearchFocused: $isSearchFocused)
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 520)

            DetailView(item: viewModel.selectedItem)
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .frame(minWidth: 1080, minHeight: 720)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(AppViewModel.SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.regular)
            }

            ToolbarItemGroup(placement: .principal) {
                ToolbarSearchField(text: $viewModel.searchText, isFocused: $isSearchFocused)
                    .frame(width: 360)
                    .frame(minWidth: 320, maxWidth: 420)
                    .focusable()
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await viewModel.loadFromBridge() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .frame(width: 28, height: 28)
                .controlSize(.large)
                .buttonStyle(.borderless)
                .help("Refresh")

                Button {
                    Task { await viewModel.runProcessingPipeline() }
                } label: {
                    Image(systemName: viewModel.isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                }
                .frame(width: 28, height: 28)
                .controlSize(.large)
                .buttonStyle(.borderless)
                .disabled(viewModel.isSyncing)
                .help(viewModel.isSyncing ? "Syncing..." : "Sync")

                Menu {
                    Button("Open Job Link") {
                        if let item = viewModel.selectedItem {
                            viewModel.openJobLink(for: item)
                        }
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button("Open Source File") {
                        if let item = viewModel.selectedItem {
                            viewModel.openSourceFile(for: item)
                        }
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                    Divider()

                    Text(viewModel.dataSourceLabel)
                        .foregroundStyle(.secondary)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(width: 28, height: 28)
                .controlSize(.large)
                .buttonStyle(.borderless)
                .help("More")

                Button("Focus Search") {
                    isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
            }
        }
        .task {
            await viewModel.loadFromBridge()
        }
    }
}

private struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = "Search company, role, location"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused, nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !isFocused, nsView.window?.firstResponder === nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isFocused = false
        }
    }
}
