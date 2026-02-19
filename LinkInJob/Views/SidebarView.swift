import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    private let rowCornerRadius: CGFloat = 12

    var body: some View {
        List {
            Section("Stages") {
                stageRow(.inbox, shortcut: "1")
                stageRow(.applied, shortcut: "2")
                stageRow(.interview, shortcut: "3")
                stageRow(.offer, shortcut: "4")
                stageRow(.rejected, shortcut: "5")
                stageRow(.archive, shortcut: "6")
            }

            Section("Smart Filters") {
                smartRow(.starred, count: viewModel.starredCount)
                smartRow(.noReply, count: viewModel.noReplyCount)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func filterRowContent(
        title: String,
        symbol: String,
        symbolColor: Color,
        count: Int,
        isSelected: Bool
    ) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.28), in: Capsule())
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
            ? Color.accentColor.opacity(0.18)
            : Color.clear,
            in: RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
        )
    }

    private func stageRow(_ stage: Stage, shortcut: KeyEquivalent) -> some View {
        let filter = AppViewModel.SidebarFilter.stage(stage)
        return Button {
            viewModel.selectFilter(filter)
        } label: {
            filterRowContent(
                title: stage.title,
                symbol: stage.symbol,
                symbolColor: stage.color,
                count: viewModel.stageCounts[stage, default: 0],
                isSelected: viewModel.sidebarFilter == filter
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .keyboardShortcut(shortcut, modifiers: .command)
    }

    private func smartRow(_ filter: AppViewModel.SidebarFilter, count: Int) -> some View {
        Button {
            viewModel.selectFilter(filter)
        } label: {
            filterRowContent(
                title: filter.title,
                symbol: filter.symbol,
                symbolColor: .secondary,
                count: count,
                isSelected: viewModel.sidebarFilter == filter
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
