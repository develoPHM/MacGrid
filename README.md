# MacGrid — Tahoe 이후 런치패드 재현

macOS Tahoe에서 사라진 Launchpad를 그대로 재현한 앱. SwiftUI + AppKit, macOS 14 이상.

## 설치

Xcode가 설치돼 있어야 한다 (App Store).

```bash
cd MacGrid
./install.sh
```

빌드 후 `/Applications/MacGrid.app`으로 설치되고 바로 실행된다. 이후엔 **⌃Space**, Dock 아이콘, 메뉴 막대 아이콘으로 열고 닫는다.
로그인 시 자동 시작·단축키·메뉴 막대 아이콘은 설정(⌘,)에서 켜고 끌 수 있다.

## 동작

| 동작 | 방법 |
|---|---|
| 열기 | Dock 아이콘 클릭 (앱 실행) |
| 닫기 | ESC, 빈 곳 클릭, 다른 앱으로 전환 |
| 앱 실행 | 아이콘 클릭 |
| 페이지 이동 | 가로 드래그, 트랙패드 두 손가락 스와이프, 마우스 휠, ←/→, 하단 점 클릭 |
| 편집(흔들림) 모드 | 아이콘 0.4초 꾹 누르기 |
| 재배치 | 편집 모드에서 드래그 (다른 페이지로: 화면 좌/우 가장자리로 끌고 잠시 대기, 마지막 페이지에서 오른쪽 끝 → 새 페이지) |
| 페이지 정리 | 편집 모드 우상단 "정리" 버튼 — 모든 아이콘을 앞에서부터 꽉 채워 재배치 |
| 폴더 만들기 | 아이콘을 다른 아이콘 위(중앙)에 올려놓고 놓기 |
| 폴더에 넣기 | 아이콘을 폴더 위에 놓기 |
| 폴더에서 꺼내기 | 폴더 열고 아이콘을 패널 밖으로 드래그 |
| 폴더 페이지 | 폴더 안도 7×5씩 페이지 — 스와이프/휠/←→/점, 드래그 중엔 패널 가장자리 |
| 폴더 이름 | 폴더 열고 상단 제목 클릭 후 편집 |
| 검색 | 그냥 타이핑, Return = 첫 결과 실행 |
| 설정 | 메뉴 MacGrid → Settings…(⌘,): 배경(현재 배경화면/단색), 투명도, 흐림 |

- 앱 삭제 기능은 의도적으로 없음 (Finder에서 삭제하면 다음 열 때 자동 반영).
- 폴더에 1개만 남으면 폴더는 자동 해체.
- 배경은 시스템 배경화면 설정 파일을 읽어 표시하며, 배경을 바꾸면 다음 열 때 자동 반영.

## 스캔 범위

`/Applications`, `/System/Applications`, `~/Applications` (하위 폴더 2단계까지, Utilities 포함).
아이콘은 `NSWorkspace`, 이름은 각 앱 번들의 로컬라이즈 파일을 시스템 언어 순서로 읽어 Finder와 동일하게 표시.

## 저장 위치

배치(페이지/폴더)는 `~/Library/Application Support/MacGrid/layout.json`.
초기화하려면 이 파일을 지우면 된다 (이름순으로 다시 채워짐).

## 파일 구성

| 파일 | 역할 |
|---|---|
| `MacGridApp.swift` | 진입점, 전체화면 창, 키보드/스크롤 모니터, 표시/숨김 |
| `AppSettings.swift` / `SettingsView.swift` | 설정값(UserDefaults)과 설정 창 |
| `WallpaperCapture.swift` | 현재 배경화면 이미지 찾기 |
| `AppScanner.swift` | 응용 프로그램 폴더 스캔 |
| `LayoutStore.swift` | 페이지·폴더 모델 편집, 정리, JSON 저장, 앱 변경 반영 |
| `UIState.swift` | 페이지/편집모드/폴더/검색/스와이프 상태 |
| `DragController.swift` | 드래그 재배치·폴더 생성·페이지 넘김 로직 |
| `LaunchpadRoot.swift` | 루트 뷰, 페이저, 검색창, 페이지 점, 고스트, 배경 |
| `IconCell.swift` | 아이콘 셀(제스처), 아이콘/폴더 아이콘 그림, 흔들림 |
| `FolderOverlay.swift` | 열린 폴더 패널 |
| `Models.swift` | 데이터 모델, 그리드 좌표 계산 |
