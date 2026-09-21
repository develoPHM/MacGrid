import Carbon

/// 전역 단축키 (Carbon RegisterEventHotKey — 손쉬운 사용 권한 불필요)
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handlerRef)
        let id = EventHotKeyID(signature: 0x4D475244 /* MGRD */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let r = hotKeyRef { UnregisterEventHotKey(r) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
