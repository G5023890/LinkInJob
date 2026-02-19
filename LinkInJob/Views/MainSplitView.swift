import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) { Divider() }
        } content: {
            ApplicationListView()
                .navigationSplitViewColumnWidth(min: 380, ideal: 430, max: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) { Divider() }
        } detail: {
            DetailView(item: viewModel.selectedItem)
                .navigationSplitViewColumnWidth(min: 480, ideal: 640)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            WindowFrameAutosaveInstaller(autosaveName: "LinkInJob.MainWindow")
        )
        .frame(minWidth: 1080, minHeight: 720)
        .task {
            columnVisibility = .all
            await viewModel.loadFromBridge()
        }
    }
}
