import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingSubtitleWindowController: ObservableObject {
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private weak var viewModel: TranscriptionViewModel?

    func bind(to viewModel: TranscriptionViewModel) {
        guard self.viewModel !== viewModel else { return }
        self.viewModel = viewModel
        observe(viewModel)
    }

    func setVisible(_ isVisible: Bool, using viewModel: TranscriptionViewModel) {
        bind(to: viewModel)

        if isVisible {
            present(using: viewModel)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func observe(_ viewModel: TranscriptionViewModel) {
        cancellables.removeAll()

        viewModel.$floatingOverlayEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                guard let self, let viewModel = self.viewModel else { return }
                if isVisible {
                    self.present(using: viewModel)
                } else {
                    self.panel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        viewModel.$floatingOverlayClickThroughEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.panel?.ignoresMouseEvents = isEnabled
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(viewModel.$floatingOverlayFontScale, viewModel.$floatingOverlayLineCount)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self, let viewModel = self.viewModel else { return }
                self.updateMinimumSize(using: viewModel)
            }
            .store(in: &cancellables)
    }

    private func present(using viewModel: TranscriptionViewModel) {
        let panel = makePanelIfNeeded()
        updateMinimumSize(using: viewModel)
        panel.ignoresMouseEvents = viewModel.floatingOverlayClickThroughEnabled
        panel.contentViewController = NSHostingController(rootView: FloatingSubtitleOverlayView(viewModel: viewModel))
        panel.orderFrontRegardless()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: defaultFrame(),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("FloatingSubtitleOverlayFrame")

        self.panel = panel
        return panel
    }

    private func updateMinimumSize(using viewModel: TranscriptionViewModel) {
        let minHeight = max(180.0, (Double(viewModel.floatingOverlayLineCount) * 34.0 * viewModel.floatingOverlayFontScale) + 120.0)
        let minSize = NSSize(width: 680, height: minHeight)
        panel?.contentMinSize = minSize

        if let panel, panel.frame.height < minHeight {
            var frame = panel.frame
            frame.origin.y -= (minHeight - frame.height)
            frame.size.height = minHeight
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private func defaultFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(980.0, screenFrame.width - 120)
        let height = 250.0
        let x = screenFrame.midX - (width / 2)
        let y = screenFrame.minY + 70
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
