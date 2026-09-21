import AppKit

/// Finder의 응용 프로그램 폴더를 스캔해 앱 목록을 만든다.
enum AppScanner {
    static var roots: [String] {
        ["/Applications",
         "/System/Applications",
         NSHomeDirectory() + "/Applications"]
    }

    static func scan() -> [AppEntry] {
        var found: [String: AppEntry] = [:]
        let fm = FileManager.default

        func visit(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names where !n.hasPrefix(".") {
                let p = dir + "/" + n
                if n.hasSuffix(".app") {
                    guard let bundle = Bundle(path: p) else { continue }
                    let name = localizedName(of: bundle) ?? fm.displayName(atPath: p)
                    found[p] = AppEntry(path: p, name: name, icon: flatIcon(for: p))
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                        visit(p, depth: depth + 1)
                    }
                }
            }
        }

        roots.forEach { visit($0, depth: 0) }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// NSWorkspace 아이콘은 16~1024px 표현을 전부 들고 있어 앱당 수 MB 를 잡는다.
    /// 화면에 그리는 최대 크기(128pt × 화면 배율) 비트맵 하나로 눌러서 보관한다. (1x 화면 64KB, 2x 256KB)
    /// 모니터를 바꿔 배율이 달라지면(1x↔2x) 값이 바뀌고, reconcile 이 아이콘을 다시 만든다
    static var iconPx: Int { Int(128 * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)) }

    private static func flatIcon(for path: String) -> NSImage {
        let src = NSWorkspace.shared.icon(forFile: path)
        let px = iconPx
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return src }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: 128, height: 128))
        out.addRepresentation(rep)
        return out
    }

    // MARK: 사용자 언어로 앱 이름 찾기

    /// FileManager.displayName 은 "우리 프로세스"의 언어를 따르므로, 사용자 시스템 언어 순서로
    /// 앱 번들의 InfoPlist.strings(일반 앱) / InfoPlist.loctable(시스템 앱)을 직접 읽는다.
    private static let userLangs: [String] = {
        var out: [String] = []
        for l in Locale.preferredLanguages {           // 예: ["ko-KR", "en-US"]
            out.append(l)
            let base = String(l.split(separator: "-")[0])   // "ko"
            if !out.contains(base) { out.append(base) }
        }
        return out
    }()

    private static func localizedName(of bundle: Bundle) -> String? {
        let keys = ["CFBundleDisplayName", "CFBundleName"]

        // 1) <lang>.lproj/InfoPlist.strings
        let available = bundle.localizations
        let preferred = Bundle.preferredLocalizations(from: available, forPreferences: userLangs)
        for loc in preferred {
            if let url = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: loc),
               let d = NSDictionary(contentsOf: url) as? [String: Any] {
                for k in keys { if let v = d[k] as? String, !v.isEmpty { return v } }
            }
        }

        // 2) Resources/InfoPlist.loctable (macOS 14+ 시스템 앱: { "ko": {...}, "en": {...} })
        if let url = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
           let table = NSDictionary(contentsOf: url) as? [String: Any] {
            for loc in userLangs {
                if let d = table[loc] as? [String: Any] {
                    for k in keys { if let v = d[k] as? String, !v.isEmpty { return v } }
                }
            }
        }
        return nil
    }
}
