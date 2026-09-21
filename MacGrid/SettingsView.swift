import SwiftUI
import AppKit

/// 메뉴 MacGrid → Settings… (⌘,) 로 열리는 설정 창
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    // 슬라이더는 "투명도"로 표시: 오른쪽일수록 투명(어두움), 0 = 불투명
    private var transparency: Binding<Double> {
        Binding(get: { 1 - settings.bgOpacity }, set: { settings.bgOpacity = 1 - $0 })
    }

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 자동 시작", isOn: $settings.launchAtLogin)
                Toggle("전역 단축키  ⌃ Space", isOn: $settings.hotKeyEnabled)
                Text("입력 소스 전환(한/영)에 ⌃Space를 쓰고 있다면 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 그 항목을 끄세요.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("메뉴 막대 아이콘", isOn: $settings.showStatusItem)
            }

            Section("배경") {
                Picker("배경", selection: $settings.bgMode) {
                    Text("현재 배경화면").tag("wallpaper")
                    Text("단색").tag("solid")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if settings.bgMode == "solid" {
                    ColorPicker("색상", selection: $settings.bgColor, supportsOpacity: false)
                }

                LabeledContent("투명도") {
                    HStack {
                        Slider(value: transparency, in: 0...0.9)
                        Text("\(Int(transparency.wrappedValue * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }

                LabeledContent("흐림") {
                    HStack {
                        Slider(value: $settings.bgBlur, in: 0...60)
                        Text("\(Int(settings.bgBlur))").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(settings.bgMode != "wallpaper")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .background(WindowLevelRaiser())
    }
}

/// 설정 창을 런치패드(floating) 창보다 위로 올려 조절하면서 바로 보이게 한다.
private struct WindowLevelRaiser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
