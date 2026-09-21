import SwiftUI

/// 열린 폴더 패널
struct FolderOverlay: View {
    let folder: LPItem
    let panel: CGRect
    let grid: GridLayout

    @EnvironmentObject var store: LayoutStore
    @EnvironmentObject var ui: UIState
    @State private var name: String

    init(folder: LPItem, panel: CGRect, grid: GridLayout) {
        self.folder = folder
        self.panel = panel
        self.grid = grid
        _name = State(initialValue: folder.folderName)
    }

    var body: some View {
        let apps = folder.folderApps
        let cap = grid.capacity
        let pageCount = max(1, (apps.count + cap - 1) / cap)
        let page = min(ui.folderPage, pageCount - 1)
        let panelShape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { ui.closeFolder() }
                .transition(.opacity)

            VStack(spacing: LayoutMath.folderSpacing) {
                TextField("폴더 이름", text: $name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: LayoutMath.folderTitleH)
                    .onChange(of: name) { _, v in
                        store.renameFolder(folder.id, name: v)
                    }

                // 7x5 단위 페이지
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { pg in
                        ZStack {
                            ForEach(Array(apps.enumerated().dropFirst(pg * cap).prefix(cap)), id: \.element) { i, p in
                                IconCell(item: .app(p), context: .folder, layout: grid)
                                    .position(grid.relCenter(i - pg * cap))
                            }
                        }
                        .frame(width: grid.frame.width, height: grid.frame.height)
                    }
                }
                .offset(x: -CGFloat(page) * grid.frame.width)
                .frame(width: grid.frame.width, height: grid.frame.height, alignment: .leading)
                .clipped()
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)

                if pageCount > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<pageCount, id: \.self) { i in
                            Circle()
                                .fill(.white.opacity(i == page ? 0.95 : 0.35))
                                .frame(width: 7, height: 7)
                                .padding(5)
                                .contentShape(Rectangle())
                                .onTapGesture { ui.goToFolderPage(i) }
                        }
                    }
                    .frame(height: LayoutMath.folderDotsH - LayoutMath.folderSpacing)
                }
            }
            .frame(width: panel.width - LayoutMath.folderPad * 2)
            .padding(LayoutMath.folderPad)
            .background(
                panelShape
                    .fill(.ultraThinMaterial)
                    .overlay(panelShape.fill(.white.opacity(0.08)))
                    .overlay(panelShape.stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            )
            .position(x: panel.midX, y: panel.midY)
            .transition(.scale(scale: 0.8).combined(with: .opacity))   // 패널만 팝업처럼
        }
    }
}
