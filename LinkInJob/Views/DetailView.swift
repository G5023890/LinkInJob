import AppKit
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let item: ApplicationItem?

    @State private var descriptionQuery = ""
    @State private var showFindField = false

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HeaderCardView(item: item)

                        if item.needsFollowUp {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("No reply \(item.daysSinceLastActivity) days - Follow-up suggested")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                            .padding(10)
                            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        }

                        actionBar(item: item)

                        GroupBox("Activity") {
                            TimelineView(events: viewModel.timeline(for: item))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Description")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") {
                                        copyDescription(item)
                                    }
                                    Button("Find") {
                                        showFindField.toggle()
                                    }
                                    Button("Original Link") {
                                        viewModel.openJobLink(for: item)
                                    }
                                    .disabled(item.jobURL == nil || item.jobURL?.isEmpty == true)
                                }

                                if showFindField {
                                    TextField("Find in text", text: $descriptionQuery)
                                        .textFieldStyle(.roundedBorder)
                                }

                                if let body = filteredDescription(for: item) {
                                    ScrollView {
                                        Text(body)
                                            .font(.body)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.top, 2)
                                    }
                                    .frame(maxHeight: 320)
                                } else {
                                    Text("No description available.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Select an application", systemImage: "list.bullet.rectangle")
            }
        }
    }

    @ViewBuilder
    private func actionBar(item: ApplicationItem) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Stage.allCases, id: \.self) { stage in
                    Button(stage.title) { viewModel.setStage(stage, for: item) }
                }
            } label: {
                Label("Stage", systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)

            Button("Interview") {
                viewModel.setStage(.interview, for: item)
            }
            .keyboardShortcut("i", modifiers: [])

            Button("Reject") {
                viewModel.setStage(.rejected, for: item)
            }
            .keyboardShortcut("r", modifiers: [])

            Button("Archive") {
                viewModel.setStage(.archive, for: item)
            }
            .keyboardShortcut("a", modifiers: [])

            if item.needsFollowUp {
                Button("Follow-up") {
                    viewModel.copyFollowUp(for: item)
                }
                .keyboardShortcut("f", modifiers: [])
            }

            Menu {
                if item.jobURL != nil {
                    Button("Open Job Link") {
                        viewModel.openJobLink(for: item)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                Button("Open Source File") {
                    viewModel.openSourceFile(for: item)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(item.starred ? "Unstar" : "Star") {
                    viewModel.toggleStar(for: item)
                }
                .keyboardShortcut("s", modifiers: [])

                Button("Reset to Auto") {
                    viewModel.resetToAuto(for: item)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .buttonStyle(.bordered)
    }

    private func copyDescription(_ item: ApplicationItem) {
        guard let text = item.descriptionText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func filteredDescription(for item: ApplicationItem) -> String? {
        guard let text = item.descriptionText, !text.isEmpty else { return nil }
        guard !descriptionQuery.isEmpty else { return text }

        let lines = text.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(descriptionQuery) }

        if lines.isEmpty {
            return "No matches for \"\(descriptionQuery)\"."
        }

        return lines.joined(separator: "\n")
    }
}
