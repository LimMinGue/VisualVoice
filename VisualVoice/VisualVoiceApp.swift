import SwiftUI

@main
struct VisualVoiceApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var settings = PanelSettings()

    init() {
        #if DEBUG
        ReplaceRule.runSelfTestIfRequested()   // VV_PROBE_REPLACE=1 — 치환 규칙 자가 점검 후 종료
        WindowProbe.runIfRequested()   // VV_PROBE_FILE=… 이면 창 없이 실시간 경로 회귀 테스트 실행 후 종료
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // 메인 창 (전체 창: 사이드바 + 본문)
        WindowGroup {
            AppShellView()
                .environmentObject(app)
                .environmentObject(settings)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 700)

        // "패널로 띄우기" 팝아웃 (항상-위 플로팅)
        Window("실시간 자막", id: "caption-popout") {
            FloatingCaptionPanel()
                .environmentObject(app)
                .environmentObject(settings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 360, height: 300)
        #else
        // iPad — 대면대화(마이크) 전용 셸. 팝아웃·시스템오디오 제외
        WindowGroup {
            IPadShellView()
                .environmentObject(app)
                .environmentObject(settings)
        }
        #endif
    }
}
