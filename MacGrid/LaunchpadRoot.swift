import SwiftUI
import AppKit

// MARK: - 루트

struct LaunchpadRoot: View {
    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var drag: DragController
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = LayoutMath.page(in: size)

            ZStack {
                Background(size: size)
                    .allowsHitTesting(false)

                // 빈 영역: 탭 → 닫기, 드래그 → 페이지 스와이프
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(backgroundGesture)

                VStack(spacing: 0) {
                    SearchBar(focused: $searchFocused)
                        .frame(height: LayoutMath.topH)

                    Group {
                        if ui.query.isEmpty {
                            PagerView(width: size.width, layout: layout, motion: ui.motion)
                        } else {
                            SearchResults(layout: layout)
                        }
                    }
                    .frame(width: size.width, height: layout.frame.height)

                    PageDots()
                        .frame(height: LayoutMath.bottomH)
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(ui.visible ? 1 : 1.25)
                .opacity(ui.visible ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: ui.visible)

                if let fid = ui.openFolderID, let folder = store.item(fid) {
                    let fl = LayoutMath.folder(count: folder.folderApps.count, in: size)
                    FolderOverlay(folder: folder, panel: fl.panel, grid: fl.grid)
                        .id(fid)
                        .zIndex(1)
                }

                DragGhost(iconSize: layout.iconSize, motion: drag.motion)
                    .zIndex(2)

                // 편집 모드: 상단 "Clean Up" 버튼 — 모든 아이콘을 페이지마다 꽉 채워 재배치
                if ui.editMode && ui.openFolderID == nil {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            store.compact()
                            ui.goTo(min(ui.currentPage, store.pages.count - 1))
                        }
                    } label: {
                        Label("Clean Up", systemImage: "square.grid.3x3.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.white.opacity(0.18)))
                            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, (LayoutMath.topH - 34) / 2)   // 검색창과 같은 높이 (메뉴바에서 떨어뜨림)
                    .padding(.trailing, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(3)
                }
            }
            .coordinateSpace(name: "root")
            // ponytail: 루트 전체 .animation(value:) 은 쓰지 않는다 — 폴더/편집모드 전환 때 화면 전체가 다시 움직여 보인다.
            // 전환은 각 뷰의 .transition + 상태 변경 시 withAnimation 으로만.
            .onChange(of: geo.size, initial: true) { _, s in
                drag.screenSize = s
                ui.pageWidth = s.width
            }
            .onChange(of: ui.visible, initial: true) { _, v in
                if v { searchFocused = true }
            }
        }
        .ignoresSafeArea()
    }

    private var backgroundGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("root"))
            .onChanged { v in
                guard !drag.isActive, ui.query.isEmpty else { return }
                ui.swipeChanged(v.translation.width)
            }
            .onEnded { v in
                if abs(v.translation.width) < 6 && abs(v.translation.height) < 6 {
                    ui.backgroundTapped()
                } else if ui.query.isEmpty {
                    ui.swipeEnded(v.translation.width, predicted: v.predictedEndTranslation.width)
                }
            }
    }

}

// MARK: - 페이저 (스와이프 오프셋만 관찰 → 스와이프 중 이 뷰만 다시 그림)

struct PagerView: View {
    let width: CGFloat
    let layout: GridLayout
    @ObservedObject var motion: PagerMotion
    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState

    var body: some View {
        let page = min(ui.currentPage, store.pages.count - 1)
        HStack(spacing: 0) {
            ForEach(store.pages.indices, id: \.self) { p in
                PageGrid(page: p, layout: layout)
                    .frame(width: width, height: layout.frame.height)
            }
        }
        .offset(x: -CGFloat(max(page, 0)) * width + motion.swipeOffset)
        .frame(width: width, height: layout.frame.height, alignment: .leading)
        .clipped()
    }
}

// MARK: - 페이지 그리드

struct PageGrid: View {
    let page: Int
    let layout: GridLayout
    @EnvironmentObject var store: LayoutStore

    var body: some View {
        let items = page < store.pages.count ? store.pages[page] : []
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                IconCell(item: item, context: .page, layout: layout)
                    .position(layout.relCenter(i))
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
    }
}

// MARK: - 검색 결과

struct SearchResults: View {
    let layout: GridLayout
    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState

    var body: some View {
        let results = Array(store.search(ui.query).prefix(layout.capacity))
        ZStack {
            if results.isEmpty {
                Text("No Results")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(Array(results.enumerated()), id: \.element.path) { i, e in
                IconCell(item: .app(e.path), context: .search, layout: layout)
                    .position(layout.relCenter(i))
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
    }
}

// MARK: - 검색창

struct SearchBar: View {
    @EnvironmentObject var ui: UIState
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: $ui.query, prompt: Text("Search").foregroundColor(.white.opacity(0.75)))
                .textFieldStyle(.plain)
                .foregroundColor(.white)   // macOS TextField 입력 글자색은 foregroundColor 로 지정해야 먹는다
                .tint(.white)              // 커서/선택 색
                .focused(focused)
            if !ui.query.isEmpty {
                Button { ui.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 300, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        )
    }
}

// MARK: - 페이지 점

struct PageDots: View {
    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<store.pages.count, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == ui.currentPage ? 0.95 : 0.35))
                    .frame(width: 8, height: 8)
                    .padding(6)
                    .contentShape(Rectangle())
                    .onTapGesture { ui.goTo(i) }
            }
        }
    }
}

// MARK: - 드래그 고스트

struct DragGhost: View {
    let iconSize: CGFloat
    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var drag: DragController
    @ObservedObject var motion: DragMotion

    var body: some View {
        if let id = drag.itemID, motion.located {
            let item = store.item(id) ?? .app(id)
            IconVisual(item: item, size: iconSize)
                .scaleEffect(1.15)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                .position(motion.location)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 배경 (현재 배경화면 / 단색, 투명도·흐림은 설정)

struct Background: View {
    let size: CGSize
    @EnvironmentObject var ui: UIState
    @ObservedObject var settings = AppSettings.shared
    @State private var blurred: NSImage?   // 흐림을 미리 구운 이미지 (.blur 레이어는 전체화면 버퍼를 수십 MB 잡는다)

    var body: some View {
        Group {
            if settings.bgMode == "solid" {
                settings.bgColor
            } else if let img = ui.wallpaper {
                Image(nsImage: blurred ?? img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(Color.black.opacity(0.2))   // 아이콘 가독성
                    .task(id: "\(ObjectIdentifier(img).hashValue)-\(settings.bgBlur)") {
                        blurred = await WallpaperCapture.blurred(img, radius: settings.bgBlur)
                    }
            } else {
                settings.bgColor   // 배경화면 파일을 못 찾았을 때 폴백 (뒤가 비치지 않게 불투명)
            }
        }
        .opacity(settings.bgOpacity)   // 창 배경이 검정이라 낮출수록 어두워진다
    }
}
