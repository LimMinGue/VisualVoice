#if os(macOS)  // macOS 커스텀 셸 — iPad는 IPadShellView(NavigationSplitView)가 담당 (decisions §10)
import SwiftUI

/// 메인 창 셸 — 사이드바 + 본문(홈/라이브) (decisions.md §5).
struct AppShellView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var settings: PanelSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if app.showOnboarding { OnboardingView() } else { mainShell }
    }

    private var mainShell: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Theme.hair).frame(width: 1)
            VStack(spacing: 0) {
                // sessions.json 쓰기 실패 — 어느 화면에 있든 보인다(디스크 가득 참 등 · 침묵 실패 금지 · 2026-09-11)
                if let err = app.saveError {
                    NoticeBanner(text: "세션을 저장하지 못했습니다 — \(err) 남은 저장 공간을 확인해 주세요. 지금 화면의 기록은 앱을 닫으면 사라질 수 있어요.",
                                 color: Theme.rec, icon: "externaldrive.badge.exclamationmark")
                }
                if let notice = app.storeNotice {
                    NoticeBanner(text: notice, color: Theme.rec, icon: "doc.badge.exclamationmark")
                }
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
            }
            .background(Theme.bgMain)
        }
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.bgMain)
        // 메인 창 가림 감지 → 팝아웃 자동 표시(decisions §8 / wargame popout_auto_show)
        .background(WindowEventObserver(onOcclusion: { app.mainWindowOccluded = $0 }))
        .onChange(of: app.mainWindowOccluded) { _, _ in syncPopout() }
        .onChange(of: app.sessionState) { _, _ in syncPopout() }
        .task { app.preheatDefaultLanguage() }   // 실행 즉시 기본 언어 모델 사전 설치+예열(백그라운드)
    }

    /// 창 가림·세션 상태에 따라 팝아웃을 자동 표시/닫기 (승인된 조율안 — decisions §8).
    private func syncPopout() {
        let want = settings.autoShowPopout && app.sessionState == .recording
            && app.mainWindowOccluded && !app.popoutManuallyClosed
        if want && !app.popoutOpen {
            app.popoutAutoShown = true
            openWindow(id: "caption-popout")
        } else if !want && app.popoutAutoShown && app.popoutOpen && !app.popoutUserMoved {
            dismissWindow(id: "caption-popout")   // 복귀·세션종료·설정끔 → 자동 닫기(사용자가 옮긴 팝아웃은 유지)
        }
    }
}
#endif
