import AppKit
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let item: ApplicationItem?

    @State private var descriptionQuery = ""
    @State private var showFindField = false
    @State private var showOriginalDescription = false

    private let cardCornerRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
            Divider()

            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHeader(item)
                        followUpBanner(item)
                        actionBar(item)
                        descriptionSection(item)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView("Select an application", systemImage: "list.bullet.rectangle")
            }
        }
        .onChange(of: item?.id) { _, _ in
            showOriginalDescription = false
            descriptionQuery = ""
            showFindField = false
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 10) {
            Text("Job Details")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            if !viewModel.syncStatusText.isEmpty {
                Text(viewModel.syncStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
                    if let item {
                        viewModel.openJobLink(for: item)
                    }
                }
                .disabled(item?.jobURL == nil || item?.jobURL?.isEmpty == true)
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Source File") {
                    if let item {
                        viewModel.openSourceFile(for: item)
                    }
                }
                .disabled(item == nil)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func detailHeader(_ item: ApplicationItem) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.company)
                    .font(.title.bold())
                    .lineLimit(2)

                Text(item.role)
                    .font(.headline)
                    .lineLimit(2)

                Text(item.location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    StatusPill(stage: item.effectiveStage)

                    if let date = item.appliedDate ?? item.lastActivityDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(item.daysSinceLastActivity) days ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            compactActivitySection(item)
                .frame(width: 290, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    private func followUpBanner(_ item: ApplicationItem) -> some View {
        if item.needsFollowUp {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemOrange))
                Text("No reply \(item.daysSinceLastActivity) days — Follow-up suggested")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .systemYellow).opacity(0.18),
                in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func actionBar(_ item: ApplicationItem) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Stage.allCases, id: \.self) { stage in
                    Button(stage.title) {
                        viewModel.setStage(stage, for: item)
                    }
                }
            } label: {
                Label("Change Stage", systemImage: "arrow.triangle.2.circlepath")
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)

            Button("Archive") {
                viewModel.setStage(.archive, for: item)
            }
            .buttonStyle(.bordered)

            Button("Delete", role: .destructive) {
                viewModel.delete(item: item)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func compactActivitySection(_ item: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.headline)
            TimelineView(events: viewModel.timeline(for: item), compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func descriptionSection(_ item: ApplicationItem) -> some View {
        let text = filteredDescription(for: item) ?? ""

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Description")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Copy") { copyDescription(item) }

                    Button(showFindField ? "Hide Find" : "Find") {
                        showFindField.toggle()
                    }

                    Button {
                        showOriginalDescription = false
                        viewModel.translateDescriptionToRussian(for: item)
                    } label: {
                        if viewModel.isDescriptionTranslating(for: item) {
                            Label("Translating…", systemImage: "hourglass")
                        } else {
                            Text("Translate to Russian")
                        }
                    }
                    .disabled(!viewModel.canTranslateDescriptionToRussian(for: item) || viewModel.isDescriptionTranslating(for: item))

                    Button(showOriginalDescription ? "Show Russian" : "Show Original") {
                        showOriginalDescription.toggle()
                    }
                    .disabled((item.originalDescriptionText ?? "").isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.large)
            }

            if showFindField {
                TextField("Find in text", text: $descriptionQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320, alignment: .leading)
            }

            if text.isEmpty {
                Text("No description available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
    }

    private func copyDescription(_ item: ApplicationItem) {
        guard let text = activeDescriptionText(for: item), !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func filteredDescription(for item: ApplicationItem) -> String? {
        guard let text = activeDescriptionText(for: item), !text.isEmpty else { return nil }
        guard !descriptionQuery.isEmpty else { return text }

        let lines = text.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(descriptionQuery) }
        if lines.isEmpty {
            return "No matches for \"\(descriptionQuery)\"."
        }
        return lines.joined(separator: "\n")
    }

    private func activeDescriptionText(for item: ApplicationItem) -> String? {
        if showOriginalDescription {
            return item.originalDescriptionText ?? item.descriptionText
        }
        return item.descriptionText ?? item.originalDescriptionText
    }
}
