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

public enum QuickPasteHotKey: CaseIterable, Equatable, Sendable {
    case slot1
    case slot2
    case slot3
    case slot4
    case slot5
    case slot6
    case slot7
    case slot8
    case slot9

    public init?(slotIndex: Int) {
        switch slotIndex {
        case 1: self = .slot1
        case 2: self = .slot2
        case 3: self = .slot3
        case 4: self = .slot4
        case 5: self = .slot5
        case 6: self = .slot6
        case 7: self = .slot7
        case 8: self = .slot8
        case 9: self = .slot9
        default: return nil
        }
    }

    public var slotIndex: Int {
        switch self {
        case .slot1: 1
        case .slot2: 2
        case .slot3: 3
        case .slot4: 4
        case .slot5: 5
        case .slot6: 6
        case .slot7: 7
        case .slot8: 8
        case .slot9: 9
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .slot1: UInt32(kVK_ANSI_1)
        case .slot2: UInt32(kVK_ANSI_2)
        case .slot3: UInt32(kVK_ANSI_3)
        case .slot4: UInt32(kVK_ANSI_4)
        case .slot5: UInt32(kVK_ANSI_5)
        case .slot6: UInt32(kVK_ANSI_6)
        case .slot7: UInt32(kVK_ANSI_7)
        case .slot8: UInt32(kVK_ANSI_8)
        case .slot9: UInt32(kVK_ANSI_9)
        }
    }

    fileprivate static let modifiers = UInt32(optionKey | cmdKey)
}

public enum QuickPasteHotKeyError: Error, Equatable, Sendable {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

public enum PasteStackHotKey: String, Sendable {
    case next = "optionShiftCommandV"

    fileprivate var keyCode: UInt32 { UInt32(kVK_ANSI_V) }
    fileprivate var modifiers: UInt32 { UInt32(optionKey | shiftKey | cmdKey) }
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

private let clipFlowQuickPasteHotKeySignature: OSType = 0x434c5150

@MainActor
public final class QuickPasteHotKeyController {

    private var hotKeyReferences: [Int: EventHotKeyRef] = [:]
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor @Sendable (Int) -> Void)?

    public init() {}

    isolated deinit {
        unregister()
    }

    public func register(
        action: @escaping @MainActor @Sendable (Int) -> Void
    ) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            clipFlowQuickPasteHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            throw QuickPasteHotKeyError.eventHandlerInstallationFailed(handlerStatus)
        }

        for shortcut in QuickPasteHotKey.allCases {
            let identifier = EventHotKeyID(
                signature: clipFlowQuickPasteHotKeySignature,
                id: UInt32(shortcut.slotIndex)
            )
            var reference: EventHotKeyRef?
            let registrationStatus = RegisterEventHotKey(
                shortcut.keyCode,
                QuickPasteHotKey.modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard registrationStatus == noErr, let reference else {
                unregister()
                throw QuickPasteHotKeyError.registrationFailed(registrationStatus)
            }
            hotKeyReferences[shortcut.slotIndex] = reference
        }
    }

    public func unregister() {
        for reference in hotKeyReferences.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        action = nil
    }

    fileprivate func invoke(slotIndex: Int) {
        action?(slotIndex)
    }
}

private let clipFlowQuickPasteHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard parameterStatus == noErr,
          identifier.signature == clipFlowQuickPasteHotKeySignature,
          QuickPasteHotKey(slotIndex: Int(identifier.id)) != nil else {
        return OSStatus(eventNotHandledErr)
    }
    let controller = Unmanaged<QuickPasteHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.invoke(slotIndex: Int(identifier.id))
    }
    return noErr
}

@MainActor
public final class PasteStackHotKeyController {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor @Sendable () -> Void)?

    public init() {}

    isolated deinit {
        unregister()
    }

    public func register(action: @escaping @MainActor @Sendable () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            clipFlowPasteStackHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: 0x43505354, id: 1)
        let registrationStatus = RegisterEventHotKey(
            PasteStackHotKey.next.keyCode,
            PasteStackHotKey.next.modifiers,
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

private let clipFlowPasteStackHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<PasteStackHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.invoke()
    }
    return noErr
}
