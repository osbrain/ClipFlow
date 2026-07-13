import Carbon
import Foundation

public enum HotKeyShortcut: String, CaseIterable, Codable, Sendable {
    case commandShiftV
    case optionCommandV
    case optionCommandSpace
    case controlOptionSpace
    case optionCommandC

    fileprivate var keyCode: UInt32 {
        switch self {
        case .commandShiftV, .optionCommandV:
            return UInt32(kVK_ANSI_V)
        case .optionCommandSpace, .controlOptionSpace:
            return UInt32(kVK_Space)
        case .optionCommandC:
            return UInt32(kVK_ANSI_C)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .commandShiftV:
            return UInt32(cmdKey | shiftKey)
        case .optionCommandV, .optionCommandSpace, .optionCommandC:
            return UInt32(optionKey | cmdKey)
        case .controlOptionSpace:
            return UInt32(controlKey | optionKey)
        }
    }
}

public enum GlobalHotKeyError: Error, Equatable, Sendable {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
public final class GlobalHotKeyController {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor @Sendable () -> Void)?

    public init() {}

    isolated deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    public func register(
        shortcut: HotKeyShortcut,
        action: @escaping @MainActor @Sendable () -> Void
    ) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            clipFlowHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: 0x434c5046, id: 1)
        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            unregister()
            throw GlobalHotKeyError.registrationFailed(registrationStatus)
        }
    }

    public func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        action = nil
    }

    fileprivate func invoke() {
        action?()
    }
}

private let clipFlowHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.invoke()
    }
    return noErr
}
