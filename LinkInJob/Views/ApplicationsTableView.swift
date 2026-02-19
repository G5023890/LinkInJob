import AppKit
import SwiftUI

struct ApplicationsTableView: NSViewRepresentable {
    @Binding var selectedItemID: UUID?
    let items: [ApplicationItem]
    let onSelect: (ApplicationItem?) -> Void
    let onToggleStar: (ApplicationItem) -> Void
    let onSetStage: (ApplicationItem, Stage) -> Void
    let onOpenJobLink: (ApplicationItem) -> Void
    let onOpenSourceFile: (ApplicationItem) -> Void
    let onResetToAuto: (ApplicationItem) -> Void
    let onOpenByDoubleClick: (ApplicationItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView(frame: .zero)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 32
        tableView.floatsGroupRows = false
        tableView.selectionHighlightStyle = .regular
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.headerView = nil

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.minWidth = column.minWidth
            tableColumn.width = context.coordinator.restoredWidth(for: column)
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        scrollView.documentView = tableView

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        context.coordinator.attach(tableView: tableView)
        context.coordinator.apply(items: items, selectedID: selectedItemID)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, selectedID: selectedItemID)
    }
}

extension ApplicationsTableView {
    enum Column: String, CaseIterable {
        case summary

        var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

        var title: String {
            switch self {
            case .summary: return "Application"
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .summary: return 260
            }
        }

        var defaultWidth: CGFloat {
            switch self {
            case .summary: return 560
            }
        }

        var widthDefaultsKey: String {
            "app.table.columnWidth.\(rawValue)"
        }
    }
}

extension ApplicationsTableView {
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: ApplicationsTableView
        private var items: [ApplicationItem] = []
        private weak var tableView: NSTableView?
        private let defaults = UserDefaults.standard
        private var isApplyingSelection = false

        init(parent: ApplicationsTableView) {
            self.parent = parent
        }

        func attach(tableView: NSTableView) {
            self.tableView = tableView
        }

        func apply(items: [ApplicationItem], selectedID: UUID?) {
            self.items = items
            tableView?.reloadData()
            applySelection(id: selectedID)
        }

        func restoredWidth(for column: Column) -> CGFloat {
            let value = defaults.double(forKey: column.widthDefaultsKey)
            if value > 0 {
                return max(column.minWidth, CGFloat(value))
            }
            return column.defaultWidth
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < items.count else { return nil }
            let item = items[row]
            let column = Column(rawValue: tableColumn?.identifier.rawValue ?? "")

            switch column {
            case .summary:
                return textCell(
                    id: "summaryCell",
                    text: "\(item.company), \(item.role)",
                    tableView: tableView,
                    font: .systemFont(ofSize: 13)
                )
            case .none:
                return nil
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < items.count else {
                parent.selectedItemID = nil
                parent.onSelect(nil)
                return
            }
            let item = items[row]
            parent.selectedItemID = item.id
            parent.onSelect(item)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let appColumn = Column(rawValue: column.identifier.rawValue) else {
                return
            }
            defaults.set(Double(column.width), forKey: appColumn.widthDefaultsKey)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let item = selectedOrClickedItem() else { return }

            let stageItem = NSMenuItem(title: "Set Stage", action: nil, keyEquivalent: "")
            let stageMenu = NSMenu(title: "Set Stage")
            for stage in Stage.allCases {
                let menuItem = NSMenuItem(title: stage.title, action: #selector(handleSetStage(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = stage.rawValue
                stageMenu.addItem(menuItem)
            }
            stageItem.submenu = stageMenu
            menu.addItem(stageItem)

            if item.jobURL != nil {
                let openLink = NSMenuItem(title: "Open Job Link", action: #selector(handleOpenJobLink), keyEquivalent: "")
                openLink.target = self
                menu.addItem(openLink)
            }

            let openSource = NSMenuItem(title: "Open Source File", action: #selector(handleOpenSourceFile), keyEquivalent: "")
            openSource.target = self
            menu.addItem(openSource)

            let toggleStar = NSMenuItem(title: item.starred ? "Unstar" : "Toggle Star", action: #selector(handleToggleStar), keyEquivalent: "")
            toggleStar.target = self
            menu.addItem(toggleStar)

            let reset = NSMenuItem(title: "Reset to Auto", action: #selector(handleResetToAuto), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let item = selectedOrClickedItem() else { return }
            parent.onOpenByDoubleClick(item)
        }

        @objc func handleSetStage(_ sender: NSMenuItem) {
            guard let item = selectedOrClickedItem(),
                  let raw = sender.representedObject as? String,
                  let stage = Stage(rawValue: raw) else {
                return
            }
            parent.onSetStage(item, stage)
        }

        @objc func handleOpenJobLink() {
            guard let item = selectedOrClickedItem() else { return }
            parent.onOpenJobLink(item)
        }

        @objc func handleOpenSourceFile() {
            guard let item = selectedOrClickedItem() else { return }
            parent.onOpenSourceFile(item)
        }

        @objc func handleToggleStar() {
            guard let item = selectedOrClickedItem() else { return }
            parent.onToggleStar(item)
        }

        @objc func handleResetToAuto() {
            guard let item = selectedOrClickedItem() else { return }
            parent.onResetToAuto(item)
        }

        private func applySelection(id: UUID?) {
            guard let tableView else { return }
            let row = id.flatMap { selectedID in
                items.firstIndex(where: { $0.id == selectedID })
            } ?? -1
            if row == tableView.selectedRow {
                return
            }
            isApplyingSelection = true
            if row >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            } else {
                tableView.deselectAll(nil)
            }
            isApplyingSelection = false
        }

        private func selectedOrClickedItem() -> ApplicationItem? {
            guard let tableView else { return nil }
            let clicked = tableView.clickedRow
            let row = clicked >= 0 ? clicked : tableView.selectedRow
            guard row >= 0, row < items.count else { return nil }
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return items[row]
        }

        private func textCell(
            id: String,
            text: String,
            tableView: NSTableView,
            font: NSFont = .systemFont(ofSize: 13),
            alignment: NSTextAlignment = .left,
            textColor: NSColor = .labelColor
        ) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier(id)
            let cell: NSTableCellView
            let textField: NSTextField
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               let existingField = existing.textField {
                cell = existing
                textField = existingField
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 1
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            textField.stringValue = text
            textField.font = font
            textField.alignment = alignment
            textField.textColor = textColor
            return cell
        }
    }
}
