import SwiftUI
import AppKit

/// 화면 상태 (페이지, 편집모드, 열린 폴더, 검색어, 스와이프)
@MainActor
final class UIState: ObservableObject {
    @Published var visible = false
    @Published var currentPage = 0
    @Published var editMode = false
    @Published var openFolderID: String? { didSet { folderPage = 0 } }
    @Published var folderPage = 0
    @Published var query = ""
    /// 고빈도 값은 별도 객체로 분리 — 페이저만 다시 그리게 해서 스와이프가 주사율대로 부드럽다
    let motion = PagerMotion()
    @Published var wallpaper: NSImage?     // 현재 배경화면 (nil이면 behind-window 블러로 폴백)

    var pageWidth: CGFloat = 1
    var onClose: (() -> Void)?
    private unowned let store: LayoutStore

    init(store: LayoutStore) { self.store = store }

    var pageCount: Int { store.pages.count }

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    func goTo(_ p: Int) {
        let c = min(max(p, 0), pageCount - 1)
        withAnimation(spring) {
            currentPage = c
            motion.swipeOffset = 0
        }
    }

    /// 열린 폴더의 페이지 수
    var folderPageCount: Int {
        guard let id = openFolderID, let f = store.item(id) else { return 1 }
        return max(1, (f.folderApps.count + LayoutStore.perPage - 1) / LayoutStore.perPage)
    }

    func goToFolderPage(_ p: Int) {
        let c = min(max(p, 0), folderPageCount - 1)
        withAnimation(spring) { folderPage = c }
    }

    /// 폴더 안 마우스 드래그: 놓을 때 거리로 한 페이지 넘김 (폴더는 손가락 따라가기 없이 한 칸씩)
    func folderSwipeEnded(_ dx: CGFloat) {
        guard abs(dx) > 50 else { return }
        goToFolderPage(folderPage + (dx < 0 ? 1 : -1))
    }

    func swipeChanged(_ dx: CGFloat) {
        var v = dx
        if (currentPage == 0 && dx > 0) || (currentPage == pageCount - 1 && dx < 0) { v = dx / 3 }
        motion.swipeOffset = v
    }

    func swipeEnded(_ dx: CGFloat, predicted: CGFloat) {
        let th = pageWidth * 0.18
        if predicted < -th || dx < -th { goTo(currentPage + 1) }
        else if predicted > th || dx > th { goTo(currentPage - 1) }
        else { goTo(currentPage) }
    }

    func closeFolder() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { openFolderID = nil }
    }

    func exitEdit() {
        withAnimation(.easeOut(duration: 0.2)) { editMode = false }
    }

    /// 폴더/편집모드가 열려 있으면 그것부터 닫고 true
    private func dismissOverlay() -> Bool {
        if openFolderID != nil { closeFolder(); return true }
        if editMode { exitEdit(); return true }
        return false
    }

    func escape() {
        if dismissOverlay() { return }
        if !query.isEmpty { query = "" } else { onClose?() }
    }

    func backgroundTapped() {
        if !dismissOverlay() { onClose?() }
    }

    func launch(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        onClose?()
    }

    func reset() {
        editMode = false
        openFolderID = nil
        query = ""
        motion.swipeOffset = 0
        currentPage = min(currentPage, max(pageCount - 1, 0))
    }
}

/// 페이지 스와이프 오프셋 (초당 수십~백 번 바뀜)
@MainActor
final class PagerMotion: ObservableObject {
    @Published var swipeOffset: CGFloat = 0
}
