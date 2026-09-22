import SwiftUI
import AppKit

/// 메뉴 MacGrid → Settings… (⌘,) 로 열리는 설정 창
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    // 슬라이더는 "Transparency"로 표시: 오른쪽일수록 투명(어두움), 0 = 불투명
    private var transparency: Binding<Double> {
        Binding(get: { 1 - settings.bgOpacity }, set: { settings.bgOpacity = 1 - $0 })
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Global Hotkey  ⌃ Space", isOn: $settings.hotKeyEnabled)
                Text("If ⌃Space is used for switching input sources, turn it off in System Settings → Keyboard → Keyboard Shortcuts → Input Sources.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Menu Bar Icon", isOn: $settings.showStatusItem)
            }

            Section("Background") {
                Picker("Background", selection: $settings.bgMode) {
                    Text("Current Wallpaper").tag("wallpaper")
                    Text("Solid Color").tag("solid")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if settings.bgMode == "solid" {
                    ColorPicker("Color", selection: $settings.bgColor, supportsOpacity: false)
                }

                LabeledContent("Transparency") {
                    HStack {
                        Slider(value: transparency, in: 0...0.9)
                        Text("\(Int(transparency.wrappedValue * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }

                LabeledContent("Blur") {
                    HStack {
                        Slider(value: $settings.bgBlur, in: 0...60)
                        Text("\(Int(settings.bgBlur))").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(settings.bgMode != "wallpaper")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 470)   // 내용이 다 보이도록 고정 높이 (스크롤 생기지 않게)
        .scrollDisabled(true)
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
