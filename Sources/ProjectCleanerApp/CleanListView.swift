import SwiftUI

struct CleanListView: View {
    @ObservedObject var viewModel: CleanerViewModel
    private let checkboxColumnWidth: CGFloat = 30
    private let typeColumnWidth: CGFloat = 112
    private let sizeColumnWidth: CGFloat = 128
    private let rowHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.hasCompletedScan && viewModel.artifacts.isEmpty && !viewModel.isScanning {
                emptyState
            } else {
                tableHeader
                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.artifacts) { artifact in
                            artifactRow(artifact)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .defaultScrollAnchor(.top)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if let hoveredPath = viewModel.hoveredPathPreview, !hoveredPath.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                    Text(hoveredPath)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.artifacts)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Files to Clean")
                .font(.headline)

            Spacer()

            Toggle("Select All", isOn: Binding(
                get: { viewModel.allItemsSelected },
                set: { viewModel.setSelectAll($0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(viewModel.artifacts.isEmpty || viewModel.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: checkboxColumnWidth)

            Text("Type")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: typeColumnWidth, alignment: .leading)

            Text("Item")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.toggleSizeSort()
            } label: {
                HStack(spacing: 4) {
                    Text("Size")
                    Image(systemName: viewModel.sizeSortDirection == .descending ? "arrow.down" : "arrow.up")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(Color.secondary.opacity(0.06))
    }

    private func artifactRow(_ artifact: CleanArtifact) -> some View {
        let selected = Binding(
            get: { viewModel.selectedArtifactIDs.contains(artifact.id) },
            set: { viewModel.setSelection($0, for: artifact.id) }
        )

        return HoverableRow { isHovered in
            HStack(spacing: 10) {
                Toggle("", isOn: selected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(viewModel.isBusy)
                    .frame(width: checkboxColumnWidth, alignment: .center)

                HStack(spacing: 6) {
                    Image(systemName: artifact.kind.symbolName)
                    Text(artifact.kind.displayName)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: typeColumnWidth, alignment: .leading)

                Text(artifact.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(viewModel.formatBytes(artifact.sizeBytes))
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: sizeColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            .onChange(of: isHovered) { _, newValue in
                viewModel.setHoveredPath(newValue ? artifact.relativePath : nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No removable cache artifacts found")
                .font(.headline)
            Text("Run another scan after your next build.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct HoverableRow<Content: View>: View {
    @State private var isHovered: Bool = false
    let content: (Bool) -> Content

    var body: some View {
        content(isHovered)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
