import SwiftUI
import AppKit
import Carbon
import Combine

@main
struct MacGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // 런치패드 창은 AppDelegate가 직접 관리. 메뉴 MacGrid → Settings… (⌘,) 는 설정 창.
        Settings { SettingsView() }
    }
}

// MARK: - 전체화면 창

final class LaunchpadWindow: NSWindow {
    init<V: View>(rootView: V) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        // 투명 창이면 macOS가 빈 영역의 클릭을 아래 창/바탕화면으로 통과시킨다 → 불투명 창으로.
        // (behindWindow 블러는 불투명 창에서도 동작)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: true)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            animator().alphaValue = 1
        }
    }

    func dismiss(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            completion()
        })
    }
}

// MARK: - 앱 델리게이트

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: LaunchpadWindow!
    private var store: LayoutStore!
    private var ui: UIState!
    private var drag: DragController!
    private var presented = false
    private var wallpaperKey = ""

    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var subs = Set<AnyCancellable>()

    private var scrollAccum: CGFloat = 0
    private var scrollVelocity: CGFloat = 0
    private var scrollLocked = false
    private var lastWheel = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = LayoutStore()
        store.load()
        store.reconcile(AppScanner.scan())   // 첫 표시 전에 동기 스캔 → 아이콘이 한 번에 뜸
        ui = UIState(store: store)
        drag = DragController(store: store, ui: ui)
        ui.onClose = { [weak self] in self?.hideLaunchpad() }

        let root = LaunchpadRoot()
            .environmentObject(store)
            .environmentObject(ui)
            .environmentObject(drag)
        window = LaunchpadWindow(rootView: root)

        // 로컬 이벤트 모니터는 항상 메인 스레드에서 불린다 (클로저는 메인액터 격리를 상속)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKey(e) ?? e
        }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.handleScroll(e)
            return e
        }

        // 편의 기능: 전역 단축키 / 메뉴 막대 아이콘 (설정에 따라 켜고 끔)
        let settings = AppSettings.shared
        settings.$hotKeyEnabled.sink { [weak self] on in self?.setHotKey(on) }.store(in: &subs)
        settings.$showStatusItem.sink { [weak self] on in self?.setStatusItem(on) }.store(in: &subs)

        // 스페이스 전환(Mission Control·세 손가락 제스처 등)은 막을 수 없으니 그때 런치패드를 닫는다
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.hideLaunchpad() } }

        // 로그인 항목으로 켜졌으면 런치패드를 띄우지 않고 조용히 대기
        if launchedAsLoginItem { NSApp.hide(nil) } else { showLaunchpad() }
    }

    /// 로그인 항목(SMAppService)에 의해 실행됐는지 — 실행 Apple Event 의 속성으로 판별
    private var launchedAsLoginItem: Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent,
              ev.eventID == AEEventID(kAEOpenApplication),
              let prop = ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else { return false }
        return prop.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    private func setHotKey(_ on: Bool) {
        hotKey = on ? HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)) { [weak self] in self?.toggleLaunchpad() } : nil
    }

    private func setStatusItem(_ on: Bool) {
        if on, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "MacGrid")
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            statusItem = item
        } else if !on, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func statusItemClicked() { toggleLaunchpad() }

    private func toggleLaunchpad() {
        if presented { hideLaunchpad() } else { showLaunchpad() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !presented { showLaunchpad() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // 다른 앱으로 전환하면 런치패드처럼 닫힘. 단, 마우스를 누른 채(드래그 중)면 무시.
        guard presented else { return }
        if NSEvent.pressedMouseButtons != 0 { return }
        hideLaunchpad()
    }

    private func showLaunchpad() {
        guard !presented else { return }
        presented = true
        ui.reset()
        store.refreshApps()
        window.present()
        let ui = self.ui!   // 클로저에는 self 대신 상수로 캡처 (Swift 6 동시성 경고 회피)
        let key = WallpaperCapture.changeKey
        if ui.wallpaper == nil || key != wallpaperKey {   // 배경화면 설정이 바뀌었을 때만 다시 로드
            wallpaperKey = key
            let screen = window.screen ?? NSScreen.main
            Task.detached(priority: .userInitiated) {
                let img = await WallpaperCapture.load(for: screen)
                await MainActor.run { ui.wallpaper = img }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            ui.visible = true
        }
    }

    private func hideLaunchpad() {
        guard presented else { return }
        presented = false
        ui.visible = false
        window.dismiss { NSApp.hide(nil) }
    }

    // MARK: 키보드

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard presented, NSApp.keyWindow === window else { return e }   // 설정 창에서는 개입 안 함
        switch e.keyCode {
        case 53: // ESC
            ui.escape()
            return nil
        case 123 where ui.query.isEmpty: // ←
            if ui.openFolderID != nil { ui.goToFolderPage(ui.folderPage - 1) } else { ui.goTo(ui.currentPage - 1) }
            return nil
        case 124 where ui.query.isEmpty: // →
            if ui.openFolderID != nil { ui.goToFolderPage(ui.folderPage + 1) } else { ui.goTo(ui.currentPage + 1) }
            return nil
        case 36 where !ui.query.isEmpty: // Return → 첫 검색 결과 실행
            if let first = store.search(ui.query).first { ui.launch(first.path) }
            return nil
        default:
            return e
        }
    }

    // MARK: 트랙패드/휠 페이지 넘김

    private func handleScroll(_ e: NSEvent) {
        guard presented, !drag.isActive, ui.query.isEmpty else { return }
        if !e.momentumPhase.isEmpty { return }

        // 폴더가 열려 있으면 폴더 페이지 넘김
        if ui.openFolderID != nil {
            if e.phase.isEmpty {   // 마우스 휠: 한 칸씩
                let d = e.scrollingDeltaX != 0 ? e.scrollingDeltaX : e.scrollingDeltaY
                if abs(d) >= 1, Date().timeIntervalSince(lastWheel) > 0.35 {
                    lastWheel = Date()
                    ui.goToFolderPage(ui.folderPage + (d < 0 ? 1 : -1))
                }
                return
            }
            if e.phase == .began { scrollAccum = 0; scrollLocked = false }
            scrollAccum += e.scrollingDeltaX
            if !scrollLocked, abs(scrollAccum) > 50 {
                scrollLocked = true
                ui.goToFolderPage(ui.folderPage + (scrollAccum < 0 ? 1 : -1))
            }
            if e.phase == .ended || e.phase == .cancelled { scrollAccum = 0; scrollLocked = false }
            return
        }

        if e.phase.isEmpty {
            // 일반 마우스 휠
            let d = e.scrollingDeltaX != 0 ? e.scrollingDeltaX : e.scrollingDeltaY
            if abs(d) >= 1, Date().timeIntervalSince(lastWheel) > 0.35 {
                lastWheel = Date()
                ui.goTo(ui.currentPage + (d < 0 ? 1 : -1))
            }
            return
        }

        // 트랙패드: 손가락을 따라 페이지가 끌려가다가, 떼는 순간 거리+속도로 넘길지 결정 (원래 Launchpad 방식)
        switch e.phase {
        case .began:
            scrollAccum = 0
            scrollVelocity = 0
        case .changed:
            scrollAccum += e.scrollingDeltaX
            scrollVelocity = e.scrollingDeltaX
            ui.swipeChanged(scrollAccum)
        case .ended, .cancelled:
            ui.swipeEnded(scrollAccum, predicted: scrollAccum + scrollVelocity * 12)
            scrollAccum = 0
        default:
            break
        }
    }
}
