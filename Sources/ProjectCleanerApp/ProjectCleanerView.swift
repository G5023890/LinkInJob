import SwiftUI

struct ProjectCleanerView: View {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some View {
        VStack(spacing: 14) {
            ProjectCardView(viewModel: viewModel)
            ScanResultView(viewModel: viewModel)
            CleanListView(viewModel: viewModel)
                .frame(minHeight: 320)
            BottomActionBar(viewModel: viewModel)
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.performInitialScanIfNeeded()
        }
        .alert("Clean \(viewModel.formattedSelectedSize) from projects?", isPresented: $viewModel.showCleanConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                viewModel.confirmClean()
            }
        } message: {
            Text("This will remove build caches and temporary files.\nSource code will NOT be touched.")
        }
    }
}
