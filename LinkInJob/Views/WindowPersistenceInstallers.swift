import AppKit
import SwiftUI

final class WindowObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if window != nil {
            onWindowChange?(window)
        }
    }
}

struct WindowFrameAutosaveInstaller: NSViewRepresentable {
    let autosaveName: String

    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName)
    }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView(frame: .zero)
        view.onWindowChange = { window in
            Task { @MainActor in
                if let window {
                    context.coordinator.bind(window: window)
                } else {
                    context.coordinator.unbind()
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = { window in
            Task { @MainActor in
                if let window {
                    context.coordinator.bind(window: window)
                } else {
                    context.coordinator.unbind()
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: WindowObserverView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    @MainActor
    final class Coordinator {
        private let frameKey: String
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var didRestore = false

        init(autosaveName: String) {
            self.frameKey = "window.frame.\(autosaveName)"
        }

        func bind(window: NSWindow) {
            guard self.window !== window else { return }
            unbind()
            self.window = window

            if !didRestore {
                restoreWindowFrame()
                didRestore = true
            }

            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.saveWindowFrame() }
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.saveWindowFrame() }
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.saveWindowFrame() }
                }
            )
            observers.append(
                center.addObserver(forName: NSApplication.willTerminateNotification, object: NSApp, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.saveWindowFrame() }
                }
            )
        }

        func unbind() {
            saveWindowFrame()
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
            window = nil
        }

        private func restoreWindowFrame() {
            guard let window else { return }
            guard let raw = UserDefaults.standard.string(forKey: frameKey) else { return }
            let frame = NSRectFromString(raw)
            guard frame.width >= 700, frame.height >= 500 else { return }
            window.setFrame(frame, display: true)
        }

        private func saveWindowFrame() {
            guard let window else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
        }
    }
}

struct SplitViewAutosaveInstaller: NSViewRepresentable {
    let autosaveName: String

    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName)
    }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView(frame: .zero)
        view.onWindowChange = { window in
            Task { @MainActor in
                if let root = window?.contentView,
                   let splitView = findMainSplitView(in: root) {
                    context.coordinator.bind(splitView: splitView)
                } else {
                    context.coordinator.unbind()
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = { window in
            Task { @MainActor in
                if let root = window?.contentView,
                   let splitView = findMainSplitView(in: root) {
                    context.coordinator.bind(splitView: splitView)
                } else {
                    context.coordinator.unbind()
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: WindowObserverView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    @MainActor
    final class Coordinator {
        private let dividersKey: String
        private weak var splitView: NSSplitView?
        private var observer: NSObjectProtocol?
        private var didRestore = false

        init(autosaveName: String) {
            self.dividersKey = "split.dividers.\(autosaveName)"
        }

        func bind(splitView: NSSplitView) {
            guard self.splitView !== splitView else { return }
            unbind()
            self.splitView = splitView

            if !didRestore {
                restoreDividers()
                didRestore = true
            }

            observer = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.saveDividers() }
            }
        }

        func unbind() {
            saveDividers()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            splitView = nil
        }

        private func restoreDividers() {
            guard let splitView else { return }
            guard let values = UserDefaults.standard.array(forKey: dividersKey) as? [Double] else { return }
            let expected = max(0, splitView.subviews.count - 1)
            guard values.count == expected else { return }

            func applyPositions() {
                for (index, value) in values.enumerated() {
                    splitView.setPosition(CGFloat(value), ofDividerAt: index)
                }
            }
            DispatchQueue.main.async { applyPositions() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyPositions() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { applyPositions() }
        }

        private func saveDividers() {
            guard let splitView else { return }
            let count = max(0, splitView.subviews.count - 1)
            guard count > 0 else { return }
            let positions = (0..<count).map { index -> Double in
                let frame = splitView.subviews[index].frame
                return splitView.isVertical ? Double(frame.maxX) : Double(frame.maxY)
            }
            UserDefaults.standard.set(positions, forKey: dividersKey)
        }
    }
}

@MainActor
private func findMainSplitView(in view: NSView) -> NSSplitView? {
    var threePane: NSSplitView?
    var twoPaneFallback: NSSplitView?

    func walk(_ node: NSView) {
        if let split = node as? NSSplitView {
            if split.subviews.count >= 3, threePane == nil {
                threePane = split
            } else if split.subviews.count >= 2, twoPaneFallback == nil {
                twoPaneFallback = split
            }
        }
        for child in node.subviews {
            walk(child)
        }
    }

    walk(view)
    return threePane ?? twoPaneFallback
}
