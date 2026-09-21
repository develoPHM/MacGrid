import AppKit
import CoreImage
import Photos

/// 현재 시스템 배경화면 이미지를 파일에서 찾는다. 권한 불필요.
///
/// Apple 내장 배경(세콰이어/Tahoe 등)은 확장 프로그램이 실시간 렌더링하므로 원본 파일이 없다.
/// 대신 설정 저장소(Index.plist)의 Provider 를 읽어 그 확장 번들 안의 대표 이미지(썸네일/폴백 heic)를 쓴다.
/// 흐림은 설정값으로 화면에서 적용하므로 썸네일 해상도로 충분하다.
enum WallpaperCapture {
    private static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// 배경화면 설정이 바뀌면 이 값이 달라진다 (설정 저장소 수정 시각 + 라이트/다크).
    /// 런치패드를 열 때 이전 값과 비교해 달라졌을 때만 다시 읽는다.
    @MainActor static var changeKey: String {
        let mtime = (try? storeURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return "\(mtime)-\(dark)"
    }

    static func load(for screen: NSScreen?) async -> NSImage? {
        let dark = await MainActor.run { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
        let target = screen?.frame.size ?? CGSize(width: 2560, height: 1600)

        // 사진 앱(Photos) 라이브러리에서 고른 배경: 파일이 없고 자산 ID만 있다 → PhotoKit (사진 접근 권한 1회)
        if let id = photosAssetID() { return await photosImage(identifier: id, targetSize: target) }

        guard let url = await userImageURL(for: screen) ?? currentWallpaperFile(dark: dark) else { return nil }
        guard let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return downscaled(cg, targetSize: target)
    }

    // MARK: 사진 앱 배경

    /// Index.plist 의 SystemDefault → Desktop → Content
    private static func currentContent() -> [String: Any]? {
        guard let data = try? Data(contentsOf: storeURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let sys = root["SystemDefault"] as? [String: Any],
              let desktop = sys["Desktop"] as? [String: Any] else { return nil }
        return desktop["Content"] as? [String: Any]
    }

    private static func photosAssetID() -> String? {
        guard let content = currentContent(),
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              (choice["Provider"] as? String)?.hasSuffix(".photos") == true,
              let blob = choice["Configuration"] as? Data,
              let cfg = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any]
        else { return nil }
        return cfg["identifier"] as? String
    }

    private static func photosImage(identifier: String, targetSize: CGSize) async -> NSImage? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier + "/L0/001", identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true   // iCloud 에만 있는 원본도 받아온다
        var result: NSImage?
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: CGSize(width: targetSize.width * 2, height: targetSize.height * 2),
                                              contentMode: .aspectFill, options: opts) { img, _ in result = img }
        return result
    }

    // MARK: 현재 배경화면 파일 찾기

    /// 사용자가 직접 고른 이미지/폴더 배경. 시스템 API가 실제 경로를 돌려준다.
    /// (Apple 내장 배경일 때는 가짜 DefaultDesktop.heic 를 주므로 그 경우는 nil → 아래 프로바이더 경로로)
    @MainActor private static func userImageURL(for screen: NSScreen?) -> URL? {
        guard let s = screen, let u = NSWorkspace.shared.desktopImageURL(for: s),
              u.lastPathComponent != "DefaultDesktop.heic" else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {   // 폴더 로테이션: 안의 첫 이미지
            let items = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
            return items.filter { imageExts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        }
        return imageExts.contains(u.pathExtension.lowercased()) ? u : nil
    }

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]

    /// provider 이름 토큰 → ExtensionKit 번들 이름
    private static let providerBundles: [String: String] = [
        "sequoia":   "WallpaperSequoiaExtension",
        "sonoma":    "WallpaperSonomaExtension",
        "ventura":   "WallpaperVenturaExtension",
        "monterey":  "WallpaperMontereyExtension",
        "macintosh": "WallpaperMacintoshExtension",
        "tahoe":     "NeptuneOneWallpaper",
        "neptune":   "NeptuneOneWallpaper",
    ]

    private static func currentWallpaperFile(dark: Bool) -> URL? {
        guard let content = currentContent(),
              let choice = (content["Choices"] as? [[String: Any]])?.first else { return nil }
        let provider = choice["Provider"] as? String ?? ""

        // 라이트/다크 변형은 시스템 외형이 아니라 배경 설정의 옵션값에 들어 있다
        var dark = dark
        if let blob = content["EncodedOptionValues"] as? Data ?? choice["Configuration"] as? Data,
           let opts = try? PropertyListSerialization.propertyList(from: blob, format: nil) {
            let desc = String(describing: opts).lowercased()
            if desc.contains("dark") { dark = true } else if desc.contains("light") { dark = false }
        }

        // 1) 사용자가 고른 이미지 파일 (Files[].relative = "file://...")
        if let files = choice["Files"] as? [[String: Any]] {
            for f in files {
                if let s = f["relative"] as? String, let u = URL(string: s),
                   imageExts.contains(u.pathExtension.lowercased()),
                   FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }

        // 2) 내장 프로바이더 → 확장 번들 안의 대표 이미지
        let token = provider.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        let extDir = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        let bundleName = providerBundles[token]
            ?? providerBundles.first { token.contains($0.key) }?.value
            ?? (try? FileManager.default.contentsOfDirectory(atPath: extDir.path))?   // 이름에 토큰이 들어간 Wallpaper 확장
                .first { $0.lowercased().contains(token) && $0.lowercased().contains("wallpaper") }
                .map { ($0 as NSString).deletingPathExtension }
        guard let bundleName else { return nil }
        return bestImage(in: extDir.appendingPathComponent("\(bundleName).appex/Contents/Resources"), dark: dark)
    }

    /// 리소스 폴더에서 현재 외형(라이트/다크)에 맞는 가장 큰 이미지
    private static func bestImage(in dir: URL, dark: Bool) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        let images = items.filter { imageExts.contains($0.pathExtension.lowercased()) }
        let want = dark ? "dark" : "light"
        let other = dark ? "light" : "dark"
        func size(_ u: URL) -> Int { (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        let matching = images.filter { $0.lastPathComponent.lowercased().contains(want) }
        let neutral = images.filter { let n = $0.lastPathComponent.lowercased(); return !n.contains(want) && !n.contains(other) }
        return (matching.max(by: { size($0) < size($1) })
                ?? neutral.max(by: { size($0) < size($1) })
                ?? images.max(by: { size($0) < size($1) }))
    }

    // MARK: 축소

    /// 흐림은 SwiftUI .blur 로 설정값에 따라 적용하므로 여기서는 화면 폭(2x)까지만 축소한다.
    private static func downscaled(_ cg: CGImage, targetSize: CGSize) -> NSImage? {
        let maxW = max(targetSize.width * 2, 1600)
        guard CGFloat(cg.width) > maxW else { return NSImage(cgImage: cg, size: targetSize) }
        let scale = maxW / CGFloat(cg.width)
        let ci = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: out, size: targetSize)
    }
}
