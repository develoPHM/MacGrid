import SwiftUI
import AppKit
import ServiceManagement

/// 사용자 설정 (UserDefaults 저장). 런치패드 창과 설정 창이 함께 본다.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // 배경
    /// "wallpaper" = 현재 배경화면, "solid" = 단색
    @Published var bgMode: String { didSet { d.set(bgMode, forKey: "bgMode") } }
    @Published var bgOpacity: Double { didSet { d.set(bgOpacity, forKey: "bgOpacity") } }
    @Published var bgBlur: Double { didSet { d.set(bgBlur, forKey: "bgBlur") } }
    @Published var bgColor: Color {
        didSet {
            let c = NSColor(bgColor).usingColorSpace(.sRGB) ?? .black
            d.set([c.redComponent, c.greenComponent, c.blueComponent], forKey: "bgColor")
        }
    }

    // 일반
    @Published var hotKeyEnabled: Bool { didSet { d.set(hotKeyEnabled, forKey: "hotKeyEnabled") } }
    @Published var showStatusItem: Bool { didSet { d.set(showStatusItem, forKey: "showStatusItem") } }
    /// 로그인 항목은 시스템(SMAppService)이 진실 — 읽을 때 상태를 묻고, 쓸 때 등록/해제
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled   // 실패하면 실제 상태로 되돌림
            }
        }
    }

    private init() {
        bgMode = d.string(forKey: "bgMode") ?? "wallpaper"
        bgOpacity = d.object(forKey: "bgOpacity") as? Double ?? 1.0
        bgBlur = d.object(forKey: "bgBlur") as? Double ?? 24
        if let rgb = d.array(forKey: "bgColor") as? [Double], rgb.count == 3 {
            bgColor = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        } else {
            bgColor = Color(red: 0.12, green: 0.12, blue: 0.14)
        }
        hotKeyEnabled = d.object(forKey: "hotKeyEnabled") as? Bool ?? true
        showStatusItem = d.object(forKey: "showStatusItem") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
