# MacGrid — Tahoe 이후 런치패드 재현

[English](README.md) | **한국어**

macOS Tahoe에서 사라진 Launchpad를 그대로 재현한 앱. SwiftUI + AppKit, macOS 26(Tahoe) 이상, Apple Silicon 전용.

![MacGrid](docs/screenshot.png)

## 설치

**요구 사항:** macOS 26(Tahoe) 이상, Apple Silicon.

### 방법 1 — 다운로드

1. [최신 릴리스](../../releases/latest)에서 `MacGrid.dmg`를 받는다.
2. 열어서 `MacGrid.app`을 `Applications`로 드래그한다.
3. 첫 실행 전에 터미널에서 한 번만:

   ```bash
   xattr -cr /Applications/MacGrid.app
   ```

   Apple Developer ID 서명이 없는 오픈소스 앱이라 Gatekeeper가 "손상됨"으로 표시하는데, 이 명령이 그 표시를 지운다.

### 방법 2 — 소스에서 빌드

Xcode가 설치돼 있어야 한다 (App Store).

```bash
git clone https://github.com/<you>/MacGrid.git
cd MacGrid
./install.sh
```

빌드 후 `/Applications/MacGrid.app`으로 설치되고 바로 실행된다. 직접 빌드한 앱은 `xattr` 단계가 필요 없다.

### 설치 후

**⌃Space**, Dock 아이콘, 메뉴 막대 아이콘으로 열고 닫는다.
로그인 시 자동 시작·단축키·메뉴 막대 아이콘은 설정(⌘,)에서 켜고 끌 수 있다.

## 동작

| 동작 | 방법 |
|---|---|
| 열기 / 닫기 | ⌃Space, Dock 아이콘, 메뉴 막대 아이콘 / ESC, 빈 곳 클릭, 다른 앱으로 전환 |
| 앱 실행 | 아이콘 클릭 |
| 페이지 이동 | 가로 드래그, 트랙패드 두 손가락 스와이프, 마우스 휠, ←/→, 하단 점 클릭 |
| 편집(흔들림) 모드 | 아이콘 0.4초 꾹 누르기 |
| 재배치 | 편집 모드에서 드래그 (다른 페이지로: 화면 좌/우 가장자리로 끌고 잠시 대기, 마지막 페이지 오른쪽 끝 → 새 페이지) |
| 페이지 정리 | 편집 모드 우상단 "Clean Up" — 모든 아이콘을 앞에서부터 꽉 채워 재배치 |
| 폴더 만들기 | 아이콘을 다른 아이콘 위(중앙)에 올려놓고 놓기 |
| 폴더에 넣기 / 꺼내기 | 아이콘을 폴더 위에 놓기 / 폴더 열고 패널 밖으로 드래그 |
| 폴더 페이지 | 폴더 안도 7×5씩 페이지 — 드래그/스와이프/휠/←→/점 |
| 폴더 이름 | 폴더 열고 상단 제목 클릭 후 편집 |
| 검색 | 그냥 타이핑, Return = 첫 결과 실행 |
| 설정 | 메뉴 MacGrid → Settings…(⌘,): 로그인 시 시작, 단축키, 메뉴 막대 아이콘, 배경(현재 배경화면/단색), 투명도, 흐림 |

- 앱 삭제 기능은 의도적으로 없음 (Finder에서 삭제하면 다음 열 때 자동 반영).
- 폴더에 1개만 남으면 폴더는 자동 해체.
- 배경은 시스템 배경화면 설정을 읽어 표시하며, 배경을 바꾸면 다음 열 때 자동 반영. 사진 앱에서 고른 배경은 사진 접근 권한을 한 번 묻는다.
- 닫은 지 1분이 지나면 다음엔 1페이지부터 열린다.

## 스캔 범위

`/Applications`, `/System/Applications`, `~/Applications` (하위 폴더 2단계까지, Utilities 포함).
이름은 각 앱 번들의 로컬라이즈 파일을 시스템 언어 순서로 읽어 Finder와 동일하게 표시.

## 저장 위치

배치(페이지/폴더)는 `~/Library/Application Support/MacGrid/layout.json`. 초기화하려면 이 파일을 지우면 된다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `MacGridApp.swift` | 진입점, 전체화면 창, 키보드/스크롤 모니터, 단축키·메뉴 막대·로그인 항목, 표시/숨김 |
| `AppSettings.swift` / `SettingsView.swift` | 설정값(UserDefaults)과 설정 창 |
| `HotKey.swift` | Carbon 전역 단축키 |
| `WallpaperCapture.swift` | 현재 배경화면 이미지 찾기 (파일 / 내장 / 사진 앱) |
| `AppScanner.swift` | 응용 프로그램 폴더 스캔 |
| `LayoutStore.swift` | 페이지·폴더 모델 편집, 정리, JSON 저장, 앱 변경 반영 |
| `UIState.swift` | 페이지/편집모드/폴더/검색/스와이프 상태 |
| `DragController.swift` | 드래그 재배치·폴더 생성·페이지 넘김 로직 |
| `LaunchpadRoot.swift` | 루트 뷰, 페이저, 검색창, 페이지 점, 고스트, 배경 |
| `IconCell.swift` | 아이콘 셀(제스처), 아이콘/폴더 아이콘 그림, 흔들림 |
| `FolderOverlay.swift` | 열린 폴더 패널 |
| `Models.swift` | 데이터 모델, 그리드 좌표 계산 |

## DMG 만들기 (배포용)

```bash
./build_dmg.sh        # → dist/MacGrid.dmg
```

DMG를 열고 `MacGrid.app`을 `Applications`로 드래그하면 설치. 단, ad-hoc 서명이라 다른 Mac에서는 첫 실행 때 Gatekeeper 경고("손상됨")가 뜨고 `xattr -cr /Applications/MacGrid.app` 또는 시스템 설정 → 개인정보 보호 및 보안에서 "그래도 열기"가 필요하다. 이건 Apple Developer ID 서명·공증 없이는 없앨 수 없다.

## 라이선스

[MIT](LICENSE)
