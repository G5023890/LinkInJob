import SwiftUI

struct ProjectCardView: View {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.directoryName)
                    .font(.title3.weight(.semibold))

                Text(viewModel.directoryDisplayPath)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Project size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(viewModel.formattedProjectSize)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                }

                Button("Change Folder…") {
                    viewModel.chooseDirectory()
                }
                .disabled(viewModel.isBusy)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
    }
}
