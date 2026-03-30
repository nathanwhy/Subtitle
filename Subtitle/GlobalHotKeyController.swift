import Carbon
import Combine
import Foundation

final class GlobalHotKeyController: ObservableObject {
    static let shortcutDescription = "Control + Option + Command + S"

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private weak var viewModel: TranscriptionViewModel?
    private let hotKeySignature = fourCharCode("SubT")
    private let hotKeyID: UInt32 = 1

    func bind(to viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
        registerIfNeeded()
    }

    deinit {
        unregister()
    }

    private func registerIfNeeded() {
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )

            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, userData in
                    guard let userData else { return noErr }
                    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                    controller.handleHotKeyEvent(event)
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }

        if hotKeyRef == nil {
            let hotKeyIdentifier = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
            RegisterEventHotKey(
                UInt32(kVK_ANSI_S),
                UInt32(controlKey | optionKey | cmdKey),
                hotKeyIdentifier,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event else { return }

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )

        guard status == noErr, identifier.signature == hotKeySignature, identifier.id == hotKeyID else {
            return
        }

        Task { @MainActor [weak self] in
            self?.viewModel?.floatingOverlayEnabled.toggle()
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf16.reduce(0) { ($0 << 8) + OSType($1) }
}
