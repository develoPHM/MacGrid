import AppKit

/// Finder에서 스캔한 앱 1개
struct AppEntry {
    let path: String
    let name: String
    let icon: NSImage
}

/// 런치패드 그리드에 놓이는 항목 (앱 또는 폴더)
struct LPItem: Identifiable, Codable, Hashable {
    enum Kind: Codable, Hashable {
        case app(path: String)
        case folder(name: String, apps: [String])
    }

    var id: String
    var kind: Kind

    static func app(_ path: String) -> LPItem {
        LPItem(id: path, kind: .app(path: path))
    }

    static func folder(name: String, apps: [String]) -> LPItem {
        LPItem(id: "folder:" + UUID().uuidString, kind: .folder(name: name, apps: apps))
    }

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    var appPath: String? {
        if case .app(let p) = kind { return p }
        return nil
    }

    var folderName: String {
        get { if case .folder(let n, _) = kind { return n }; return "" }
        set { if case .folder(_, let a) = kind { kind = .folder(name: newValue, apps: a) } }
    }

    var folderApps: [String] {
        get { if case .folder(_, let a) = kind { return a }; return [] }
        set { if case .folder(let n, _) = kind { kind = .folder(name: n, apps: newValue) } }
    }
}

/// 그리드 좌표 계산 (root 좌표계 기준 frame)
struct GridLayout {
    var frame: CGRect
    var cols: Int
    var rows: Int

    var cellW: CGFloat { frame.width / CGFloat(max(cols, 1)) }
    var cellH: CGFloat { frame.height / CGFloat(max(rows, 1)) }
    var iconSize: CGFloat { min(cellW * 0.56, cellH * 0.58, 128) }
    var capacity: Int { cols * rows }

    /// 그리드 내부 상대 좌표
    func relCenter(_ i: Int) -> CGPoint {
        CGPoint(x: (CGFloat(i % cols) + 0.5) * cellW,
                y: (CGFloat(i / cols) + 0.5) * cellH)
    }

    /// root 좌표계 절대 좌표
    func absCenter(_ i: Int) -> CGPoint {
        let c = relCenter(i)
        return CGPoint(x: frame.minX + c.x, y: frame.minY + c.y)
    }

    func slot(at p: CGPoint) -> Int? {
        guard frame.insetBy(dx: -10, dy: -10).contains(p) else { return nil }
        let col = min(max(Int((p.x - frame.minX) / cellW), 0), cols - 1)
        let row = min(max(Int((p.y - frame.minY) / cellH), 0), rows - 1)
        return row * cols + col
    }
}

enum LayoutMath {
    static let topH: CGFloat = 110
    static let bottomH: CGFloat = 70

    static func page(in size: CGSize) -> GridLayout {
        let gridH = max(size.height - topH - bottomH, 100)
        let cellH = gridH / CGFloat(LayoutStore.rows)
        let contentW = min(size.width * 0.82, cellH * CGFloat(LayoutStore.cols) * 1.25)
        return GridLayout(frame: CGRect(x: (size.width - contentW) / 2, y: topH, width: contentW, height: gridH),
                          cols: LayoutStore.cols, rows: LayoutStore.rows)
    }

    static let folderPad: CGFloat = 28
    static let folderTitleH: CGFloat = 40
    static let folderSpacing: CGFloat = 12

    static let folderDotsH: CGFloat = 24

    /// 폴더는 7x5(=35)씩 페이지로 나뉜다. 35개가 넘으면 그리드는 꽉 찬 7x5 + 하단 점 행.
    static func folder(count: Int, in size: CGSize) -> (panel: CGRect, grid: GridLayout) {
        let base = page(in: size)
        let cap = LayoutStore.perPage
        let n = min(max(count, 1), cap)
        let cols = min(LayoutStore.cols, n)
        let rows = min(LayoutStore.rows, (n + LayoutStore.cols - 1) / LayoutStore.cols)
        let cw = base.cellW, ch = base.cellH * 0.95
        let gw = cw * CGFloat(cols), gh = ch * CGFloat(rows)
        let dots: CGFloat = count > cap ? folderDotsH : 0
        let innerW = max(gw, 420)
        let panelW = innerW + folderPad * 2
        let panelH = folderTitleH + folderSpacing + gh + dots + folderPad * 2
        let panel = CGRect(x: (size.width - panelW) / 2, y: (size.height - panelH) / 2, width: panelW, height: panelH)
        let grid = GridLayout(frame: CGRect(x: (size.width - gw) / 2,
                                            y: panel.minY + folderPad + folderTitleH + folderSpacing,
                                            width: gw, height: gh),
                              cols: cols, rows: rows)
        return (panel, grid)
    }
}
