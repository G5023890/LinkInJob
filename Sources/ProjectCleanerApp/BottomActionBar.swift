import SwiftUI

struct BottomActionBar: View {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                statusItem(symbol: viewModel.primaryStatusSymbol, text: viewModel.primaryStatusLabel, isWarning: false)
                statusItem(symbol: viewModel.secondaryStatusSymbol, text: viewModel.secondaryStatusLabel, isWarning: viewModel.lastErrorMessage != nil)
            }

            Spacer(minLength: 16)

            if viewModel.isScanning || viewModel.isCleaning {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }

            Button("Rescan") {
                viewModel.rescan()
            }
            .disabled(viewModel.isBusy)

            Button("Clean \(viewModel.formattedSelectedSize)") {
                viewModel.requestClean()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canClean)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
        .animation(.easeInOut(duration: 0.18), value: viewModel.isBusy)
    }

    private func statusItem(symbol: String, text: String, isWarning: Bool) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(isWarning ? .yellow : .green)
        }
    }
}
