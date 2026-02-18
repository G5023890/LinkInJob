import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 48, maxHeight: 52)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ZStack {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(1)
                    .ignoresSafeArea()
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
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)
                .clipped()
            }
        }
        .clipped()
    }

    private func stageRow(_ stage: Stage, shortcut: KeyEquivalent) -> some View {
        let filter = AppViewModel.SidebarFilter.stage(stage)
        return Button {
            viewModel.selectFilter(filter)
        } label: {
            Label {
                HStack {
                    Text(stage.title)
                    Spacer()
                    Text("\(viewModel.stageCounts[stage, default: 0])")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.7), in: Capsule())
                }
            } icon: {
                Image(systemName: stage.symbol)
                    .foregroundStyle(stage.color)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(viewModel.sidebarFilter == filter ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .keyboardShortcut(shortcut, modifiers: .command)
    }

    private func smartRow(_ filter: AppViewModel.SidebarFilter, count: Int) -> some View {
        Button {
            viewModel.selectFilter(filter)
        } label: {
            Label {
                HStack {
                    Text(filter.title)
                    Spacer()
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.7), in: Capsule())
                }
            } icon: {
                Image(systemName: filter.symbol)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(viewModel.sidebarFilter == filter ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
