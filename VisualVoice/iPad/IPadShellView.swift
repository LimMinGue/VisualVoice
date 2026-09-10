#if os(iOS)  // iPad 전용 소스 — iPad/ 폴더로 분리 (제작자 지시 2026-07-19)
import SwiftUI

/// iPad 셸 — NavigationSplitView(가로=사이드바 병렬 · 세로=☰ 오버레이) (decisions §10 · 목업 컨펌 2026-07-18).
/// 화면 뷰(홈/라이브/상세/보관함/설정)와 사이드바는 macOS와 공용 — 셸 래퍼만 iPad 전용,
/// macOS 커스텀 셸(AppShellView)은 불변(회귀 0).
struct IPadShellView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Group {
            if app.showOnboarding {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(250)
                        .toolbar(.hidden, for: .navigationBar)   // 사이드바는 자체 브랜드 헤더 사용
                } detail: {
                    Group {
                        switch app.screen {
                        case .home: HomeView()
                        case .live: LiveSessionView()
                        case .detail: SessionDetailView()
                        case .settings: SettingsView()
                        case .archive: ArchiveView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.bgMain)
                }
                .task { app.preheatDefaultLanguage() }   // 실행 즉시 기본 언어 모델 사전 설치+예열(macOS 셸과 동일)
            }
        }
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.dark)   // 다크 단일 테마 고정 (decisions §6) — 시스템 시트·메뉴·다이얼로그까지 다크
    }
}
#endif
