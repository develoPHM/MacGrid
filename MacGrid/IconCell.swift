import SwiftUI

/// 마우스 누름 상태 추적 (탭 / 길게누름 / 드래그 / 스와이프 판별)
final class PressTracker {
    var down = false
    var dragging = false
    var swiping = false
    var lastLoc: CGPoint = .zero
    var work: DispatchWorkItem?
}

/// 그리드 셀 1개 (아이콘 + 이름)
struct IconCell: View {
    enum Context {
        case page, folder, search

        var allowsDrag: Bool {
            if case .search = self { return false }
            return true
        }
        var isPage: Bool {
            if case .page = self { return true }
            return false
        }
    }

    let item: LPItem
    let context: Context
    let layout: GridLayout

    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var drag: DragController
    @State private var tracker = PressTracker()

    var body: some View {
        let isDragged = drag.itemID == item.id
        let isTarget = drag.folderTarget == item.id
        let size = layout.iconSize

        VStack(spacing: 6) {
            IconVisual(item: item, size: size)
                .contentShape(hitShape(size))   // 클릭/드래그 판정 = 실제 보이는 아이콘 도형만
                .gesture(pressGesture)          // 제스처는 아이콘에만 부착
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(.white.opacity(isTarget ? 0.28 : 0))
                        .allowsHitTesting(false)
                )
                .scaleEffect(isTarget ? 1.1 : 1)
                .animation(.easeOut(duration: 0.15), value: isTarget)

            Text(store.name(of: item))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(layout.cellW - 12, 0))   // 초기 레이아웃(크기 0)에서 음수 방지
                .allowsHitTesting(false)
        }
        // ponytail: 바깥 프레임/제스처 없음 — 셀 빈 영역과 이름 텍스트는 클릭이 배경으로 통과
        .opacity(isDragged ? 0 : 1)
        .modifier(Jiggle(on: ui.editMode && context.allowsDrag && !isDragged))
    }

    /// macOS 앱 아이콘은 1024 캔버스 중 가운데 824px(≈80.5%) squircle 만 그려지고 나머지는 투명 여백.
    /// 그 여백을 뺀 둥근 사각형을 판정 영역으로 쓴다. (폴더 아이콘은 우리가 꽉 채워 그리므로 여백 없음)
    private func hitShape(_ size: CGFloat) -> some Shape {
        let inset = item.isFolder ? 0 : size * (1 - 824.0 / 1024.0) / 2
        let visible = size - inset * 2
        return RoundedRectangle(cornerRadius: visible * 0.225, style: .continuous)
            .inset(by: inset)
    }

    private func activate() {
        switch item.kind {
        case .app(let p):
            ui.launch(p)
        case .folder:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                ui.openFolderID = item.id
            }
        }
    }

    /// 단일 DragGesture(minimumDistance: 0)로 탭·길게누름·드래그·페이지스와이프 모두 처리
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("root"))
            .onChanged { v in
                let t = tracker
                if !t.down {
                    t.down = true
                    t.dragging = false
                    t.swiping = false
                    t.lastLoc = v.location
                    t.work?.cancel()
                    if context.allowsDrag && !ui.editMode {
                        // 0.4초 길게 누르면 편집 모드 진입 + 드래그 시작
                        let w = DispatchWorkItem {
                            guard t.down, !t.swiping, !t.dragging else { return }
                            withAnimation(.easeOut(duration: 0.2)) { ui.editMode = true }
                            t.dragging = true
                            drag.begin(item: item, at: t.lastLoc)   // 이후 이동/놓기는 DragController 가 직접 받음
                        }
                        t.work = w
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
                    }
                }
                t.lastLoc = v.location
                guard context.allowsDrag else { return }

                if t.dragging { return }   // 드래그 중 위치는 DragController 모니터가 처리
                if t.swiping {
                    ui.swipeChanged(v.translation.width)
                    return
                }
                let dist = hypot(v.translation.width, v.translation.height)
                if ui.editMode {
                    if dist > 4 {
                        t.dragging = true
                        drag.begin(item: item, at: v.location)
                    }
                    return
                }
                if dist > 10 {
                    t.work?.cancel()
                    if context.isPage {
                        t.swiping = true
                        ui.swipeChanged(v.translation.width)
                    }
                }
            }
            .onEnded { v in
                let t = tracker
                t.work?.cancel()
                t.down = false
                if t.dragging {
                    // 놓기는 DragController 의 mouseUp 모니터가 처리 (셀이 이미 파괴됐을 수 있음)
                } else if t.swiping {
                    ui.swipeEnded(v.translation.width, predicted: v.predictedEndTranslation.width)
                } else if abs(v.translation.width) < 6 && abs(v.translation.height) < 6 {
                    activate()
                }
                t.dragging = false
                t.swiping = false
            }
    }
}

// MARK: - 아이콘 그림

struct IconVisual: View {
    let item: LPItem
    let size: CGFloat
    @EnvironmentObject var store: LayoutStore

    var body: some View {
        switch item.kind {
        case .app(let p):
            if let e = store.entry(p) {
                Image(nsImage: e.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        case .folder(_, let apps):
            FolderIconVisual(apps: apps, size: size)
        }
    }
}

struct FolderIconVisual: View {
    let apps: [String]
    let size: CGFloat
    @EnvironmentObject var store: LayoutStore

    var body: some View {
        let mini = size * 0.24
        let gap = size * 0.05
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(.white.opacity(0.18)))
            .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 1))
            .overlay(
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: gap), count: 3), spacing: gap) {
                    ForEach(apps.prefix(9), id: \.self) { p in
                        if let e = store.entry(p) {
                            Image(nsImage: e.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: mini, height: mini)
                        } else {
                            Color.clear.frame(width: mini, height: mini)
                        }
                    }
                }
            )
            .frame(width: size, height: size)
    }
}

// MARK: - 흔들림

struct Jiggle: ViewModifier {
    let on: Bool
    @State private var phase = false
    @State private var delay = Double.random(in: 0...0.12)

    private var jiggleAnim: Animation {
        .easeInOut(duration: 0.14).repeatForever(autoreverses: true).delay(delay)
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (phase ? 1.8 : -1.8) : 0))
            .onAppear {
                if on { withAnimation(jiggleAnim) { phase = true } }
            }
            .onChange(of: on) { _, v in
                if v {
                    withAnimation(jiggleAnim) { phase = true }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { phase = false }
                }
            }
    }
}
