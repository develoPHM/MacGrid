import SwiftUI

/// 페이지/폴더 배치 상태 + JSON 저장
@MainActor
final class LayoutStore: ObservableObject {
    nonisolated static let cols = 7
    nonisolated static let rows = 5
    nonisolated static var perPage: Int { cols * rows }

    @Published private(set) var pages: [[LPItem]] = [[]]
    @Published private(set) var apps: [String: AppEntry] = [:]

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }()

    // MARK: 저장/로드

    func load() {
        if let d = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode([[LPItem]].self, from: d),
           !p.isEmpty {
            pages = p
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(pages) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: 앱 스캔 반영

    func refreshApps() {
        Task.detached(priority: .userInitiated) {
            let entries = AppScanner.scan()
            await MainActor.run { self.reconcile(entries) }
        }
    }

    func reconcile(_ entries: [AppEntry]) {
        var dict: [String: AppEntry] = [:]
        for e in entries { dict[e.path] = e }
        // 앱 목록이 그대로고 아이콘 해상도(화면 배율)도 그대로면 아이콘 객체를 갈아끼우지 않는다 (깜빡임 방지)
        let px = { (e: AppEntry?) in e?.icon.representations.first?.pixelsWide ?? 0 }
        if Set(dict.keys) == Set(apps.keys), px(dict.values.first) == px(apps.values.first) { return }
        apps = dict
        let known = Set(dict.keys)
        var placed = Set<String>()

        // 사라진 앱 제거, 중복 제거
        pages = pages.map { page in
            page.compactMap { item in
                switch item.kind {
                case .app(let p):
                    guard known.contains(p), !placed.contains(p) else { return nil }
                    placed.insert(p)
                    return item
                case .folder(let n, let a):
                    let kept = a.filter { known.contains($0) && !placed.contains($0) }
                    kept.forEach { placed.insert($0) }
                    if kept.isEmpty { return nil }
                    return LPItem(id: item.id, kind: .folder(name: n, apps: kept))
                }
            }
        }

        // 새 앱은 마지막에 추가
        for e in entries where !placed.contains(e.path) {
            append(.app(e.path))
        }
        normalize()
        save()
    }

    private func append(_ item: LPItem) {
        if pages.isEmpty { pages = [[]] }
        if pages[pages.count - 1].count >= Self.perPage { pages.append([]) }
        pages[pages.count - 1].append(item)
    }

    /// 페이지 초과분 밀어내기, 빈 페이지 제거
    func normalize() {
        var i = 0
        while i < pages.count {
            while pages[i].count > Self.perPage {
                let overflow = pages[i].removeLast()
                if i + 1 >= pages.count { pages.append([]) }
                pages[i + 1].insert(overflow, at: 0)
            }
            i += 1
        }
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
    }

    // MARK: 조회

    func entry(_ path: String) -> AppEntry? { apps[path] }

    func name(of item: LPItem) -> String {
        switch item.kind {
        case .app(let p): return apps[p]?.name ?? ((p as NSString).lastPathComponent as NSString).deletingPathExtension
        case .folder(let n, _): return n
        }
    }

    func item(_ id: String) -> LPItem? {
        for p in pages { if let i = p.first(where: { $0.id == id }) { return i } }
        return nil
    }

    func indexOf(_ id: String) -> (page: Int, index: Int)? {
        for (pi, p) in pages.enumerated() {
            if let i = p.firstIndex(where: { $0.id == id }) { return (pi, i) }
        }
        return nil
    }

    func search(_ q: String) -> [AppEntry] {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return [] }
        return apps.values
            .filter { $0.name.localizedCaseInsensitiveContains(t) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: 편집

    private func ensurePage(_ p: Int) {
        while pages.count <= p { pages.append([]) }
    }

    private func removeItem(_ id: String) {
        if let loc = indexOf(id) { pages[loc.page].remove(at: loc.index) }
    }

    func move(_ id: String, toPage page: Int, index: Int) {
        guard let src = indexOf(id) else { return }
        let item = pages[src.page].remove(at: src.index)
        ensurePage(page)
        let idx = min(max(index, 0), pages[page].count)
        pages[page].insert(item, at: idx)
        normalize()
    }

    func createFolder(dragging id: String, onto targetID: String) {
        guard id != targetID,
              let dragged = item(id), let path = dragged.appPath,
              let loc = indexOf(targetID) else { return }
        let (tp, ti) = (loc.page, loc.index)
        let target = pages[tp][ti]
        switch target.kind {
        case .folder(let n, var a):
            a.append(path)   // 폴더는 페이지로 늘어나므로 개수 제한 없음
            pages[tp][ti] = LPItem(id: target.id, kind: .folder(name: n, apps: a))
            removeItem(id)
            normalize()
        case .app(let targetPath):
            let f = LPItem.folder(name: "Untitled Folder", apps: [targetPath, path])
            pages[tp][ti] = f
            removeItem(id)
            normalize()
        }
    }

    /// 모든 페이지의 항목을 순서대로 앞에서부터 꽉 채워 다시 배치 (빈 자리 제거, 빈 페이지 제거)
    func compact() {
        let all = pages.flatMap { $0 }
        pages = stride(from: 0, to: all.count, by: Self.perPage).map { Array(all[$0 ..< min($0 + Self.perPage, all.count)]) }
        if pages.isEmpty { pages = [[]] }
        save()
    }

    func renameFolder(_ id: String, name: String) {
        guard let loc = indexOf(id) else { return }
        let (p, i) = (loc.page, loc.index)
        var f = pages[p][i]
        f.folderName = name
        pages[p][i] = f
        save()
    }

    func moveInFolder(_ id: String, path: String, to index: Int) {
        guard let loc = indexOf(id) else { return }
        let (p, i) = (loc.page, loc.index)
        var f = pages[p][i]
        var a = f.folderApps
        guard let ci = a.firstIndex(of: path) else { return }
        a.remove(at: ci)
        a.insert(path, at: min(max(index, 0), a.count))
        f.folderApps = a
        pages[p][i] = f
    }

    /// 폴더에서 앱을 꺼내 페이지 끝에 놓는다. 1개 남으면 폴더 해체.
    func removeFromFolder(_ id: String, path: String, toPage page: Int) {
        guard let loc = indexOf(id) else { return }
        let (p, i) = (loc.page, loc.index)
        var f = pages[p][i]
        var a = f.folderApps
        a.removeAll { $0 == path }
        if a.count <= 1 {
            pages[p].remove(at: i)
            if let last = a.first { pages[p].insert(.app(last), at: i) }
        } else {
            f.folderApps = a
            pages[p][i] = f
        }
        ensurePage(page)
        pages[page].append(.app(path))
        normalize()
    }
}
