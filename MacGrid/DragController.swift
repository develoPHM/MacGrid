import SwiftUI
import AppKit

/// 아이콘 드래그(재배치 / 폴더 생성 / 페이지 넘김 / 폴더 밖으로 꺼내기) 로직
@MainActor
final class DragController: ObservableObject {
    @Published var itemID: String?
    @Published var folderTarget: String?
    /// 드래그 위치는 고빈도라 별도 객체 — 고스트만 다시 그린다
    let motion = DragMotion()

    var screenSize: CGSize = .zero

    private unowned let store: LayoutStore
    private unowned let ui: UIState

    private var hoverIndex: Int?
    private var hoverSince = Date()
    private var targetSince = Date()
    private var edgeSince: Date?
    private var outsideSince: Date?

    private let edgeWidth: CGFloat = 40
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.8)

    init(store: LayoutStore, ui: UIState) {
        self.store = store
        self.ui = ui
    }

    var isActive: Bool { itemID != nil }
    var pageLayout: GridLayout { LayoutMath.page(in: screenSize) }

    // 드래그 중 마우스 이벤트는 셀 뷰의 제스처가 아니라 여기서 직접 받는다.
    // (페이지 넘김/폴더 밖 이동으로 셀 뷰가 파괴되면 SwiftUI 제스처가 끊기기 때문)
    private var currentItem: LPItem?
    private var monitors: [Any] = []

    func begin(item: LPItem, at location: CGPoint) {
        guard itemID == nil else { return }
        currentItem = item
        update(item: item, location: location)
        let handler: (NSEvent) -> NSEvent? = { [weak self] e in
            self?.handle(e)
            return e
        }
        monitors = [NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: handler),
                    NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: handler)]
            .compactMap { $0 }
    }

    private func handle(_ e: NSEvent) {
        guard let item = currentItem else { return }
        if e.type == .leftMouseUp { end(); return }
        guard let content = e.window?.contentView else { return }
        let p = e.locationInWindow
        // AppKit(좌하단 원점) → SwiftUI root(좌상단 원점)
        update(item: item, location: CGPoint(x: p.x, y: content.bounds.height - p.y))
    }

    func update(item: LPItem, location: CGPoint) {
        if itemID != item.id {
            itemID = item.id
            motion.located = false
            hoverIndex = nil
            folderTarget = nil
            edgeSince = nil
            outsideSince = nil
        }
        motion.location = location
        motion.located = true
        if let fid = ui.openFolderID {
            updateInFolder(item: item, folderID: fid, at: location)
        } else {
            updateOnPage(item: item, at: location)
        }
    }

    func end() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        currentItem = nil
        guard let id = itemID else { return }
        if let t = folderTarget, Date().timeIntervalSince(targetSince) > 0.12 {
            withAnimation(spring) { store.createFolder(dragging: id, onto: t) }
        }
        withAnimation(.easeOut(duration: 0.15)) {
            itemID = nil
            motion.located = false
            folderTarget = nil
        }
        hoverIndex = nil
        edgeSince = nil
        outsideSince = nil
        store.save()
    }

    // MARK: 페이지 위 드래그

    private func updateOnPage(item: LPItem, at p: CGPoint) {
        guard let loc = store.indexOf(item.id) else { return }
        let (page, idx) = (loc.page, loc.index)
        let now = Date()
        let layout = pageLayout

        // 화면 가장자리 → 페이지 넘김 (마지막 페이지에서는 새 페이지 생성)
        let atLeft = p.x < edgeWidth && page > 0
        let atRight = p.x > screenSize.width - edgeWidth
            && (page < store.pages.count - 1 || store.pages[page].count > 1)
        if atLeft || atRight {
            if let since = edgeSince {
                if now.timeIntervalSince(since) > 0.45 {
                    let target = atLeft ? page - 1 : page + 1
                    withAnimation(spring) { store.move(item.id, toPage: target, index: Int.max) }
                    if let moved = store.indexOf(item.id) { ui.goTo(moved.page) }
                    edgeSince = now.addingTimeInterval(0.7)  // 연속 넘김 쿨다운
                }
            } else {
                edgeSince = now
            }
            hoverIndex = nil
            folderTarget = nil
            return
        }
        edgeSince = nil

        guard let slot = layout.slot(at: p) else {
            hoverIndex = nil
            folderTarget = nil
            return
        }
        let items = store.pages[page]

        // 다른 아이콘 중앙에 올리면 폴더 후보
        if slot < items.count, items[slot].id != item.id, !item.isFolder {
            let c = layout.absCenter(slot)
            if hypot(p.x - c.x, p.y - c.y) < layout.iconSize * 0.42 {
                if folderTarget != items[slot].id {
                    folderTarget = items[slot].id
                    targetSince = now
                }
                hoverIndex = nil
                return
            }
        }
        folderTarget = nil

        // 재배치
        let target = min(slot, items.count - 1)
        guard target != idx else { hoverIndex = nil; return }
        if hoverIndex != target {
            hoverIndex = target
            hoverSince = now
        } else if now.timeIntervalSince(hoverSince) > 0.1 {
            withAnimation(spring) { store.move(item.id, toPage: page, index: target) }
            hoverIndex = nil
        }
    }

    // MARK: 폴더 안 드래그

    private func updateInFolder(item: LPItem, folderID: String, at p: CGPoint) {
        guard let path = item.appPath, let folder = store.item(folderID) else { return }
        let now = Date()
        let (panel, grid) = LayoutMath.folder(count: folder.folderApps.count, in: screenSize)

        if panel.contains(p) {
            outsideSince = nil
            let apps = folder.folderApps
            let cap = grid.capacity
            let pageCount = max(1, (apps.count + cap - 1) / cap)
            let page = min(ui.folderPage, pageCount - 1)

            // 패널 좌/우 가장자리 → 폴더 페이지 넘김
            let atLeft = p.x < panel.minX + edgeWidth && page > 0
            let atRight = p.x > panel.maxX - edgeWidth && page < pageCount - 1
            if atLeft || atRight {
                if let since = edgeSince {
                    if now.timeIntervalSince(since) > 0.45 {
                        ui.goToFolderPage(atLeft ? page - 1 : page + 1)
                        edgeSince = now.addingTimeInterval(0.7)
                    }
                } else { edgeSince = now }
                hoverIndex = nil
                return
            }
            edgeSince = nil

            guard let slot = grid.slot(at: p) else { hoverIndex = nil; return }
            guard let cur = apps.firstIndex(of: path) else { return }
            let target = min(page * cap + slot, apps.count - 1)
            guard target != cur else { hoverIndex = nil; return }
            if hoverIndex != target {
                hoverIndex = target
                hoverSince = now
            } else if now.timeIntervalSince(hoverSince) > 0.1 {
                withAnimation(spring) { store.moveInFolder(folderID, path: path, to: target) }
                hoverIndex = nil
            }
        } else {
            hoverIndex = nil
            if let since = outsideSince {
                if now.timeIntervalSince(since) > 0.25 {
                    outsideSince = nil
                    withAnimation(spring) {
                        store.removeFromFolder(folderID, path: path, toPage: ui.currentPage)
                        ui.openFolderID = nil
                    }
                }
            } else {
                outsideSince = now
            }
        }
    }
}

@MainActor
final class DragMotion: ObservableObject {
    @Published var located = false
    @Published var location: CGPoint = .zero
}
