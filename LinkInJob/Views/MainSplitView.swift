import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            ApplicationListView()
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 520)

            DetailView(item: viewModel.selectedItem)
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .background(
            SplitViewAutosaveInstaller(autosaveName: "LinkInJob.MainSplitView")
        )
        .background(
            WindowFrameAutosaveInstaller(autosaveName: "LinkInJob.MainWindow")
        )
        .frame(minWidth: 1080, minHeight: 720)
        .task {
            await viewModel.loadFromBridge()
        }
    }
}
