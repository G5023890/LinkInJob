import SwiftUI

struct ScanResultView: View {
    @ObservedObject var viewModel: CleanerViewModel
    private let cardHeight: CGFloat = 196

    var body: some View {
        HStack(spacing: 14) {
            summaryCard
            freeSpaceCard
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan Results")
                .font(.headline)

            metricRow(title: "Project size", value: viewModel.formattedProjectSize)
            metricRow(title: "Will be removed", value: viewModel.formattedSelectedSize)
            metricRow(title: "After cleanup", value: viewModel.formattedAfterCleanupSize)
            Spacer(minLength: 0)

            if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
    }

    private var freeSpaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You can free")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(viewModel.formattedSelectedSize)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            ProgressView(value: viewModel.cleanupProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text("Selected \(viewModel.selectedArtifactIDs.count) of \(viewModel.artifacts.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
