#if os(macOS)  // 팝아웃 = 항상-위 플로팅 창 — iPad 제외 (decisions §10)
import SwiftUI

/// "패널로 띄우기" 팝아웃 — 항상-위 플로팅, 줌 위에 겹쳐 보기 (decisions.md §5·§6).
/// 창 안 라이브 뷰와 동일한 CaptionStreamView를 공용으로 쓴다.
struct FloatingCaptionPanel: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var settings: PanelSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.rec).frame(width: 8, height: 8)
                Text("실시간 자막")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                if app.popoutAutoShown {   // 창 가림으로 자동 표시됐음을 정직하게 표기 (decisions §8)
                    Text("자동")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.accentDim, in: Capsule())
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.35)))
                }
                Spacer()
                Text(app.pair.short)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.leading, 68).padding(.trailing, 12).padding(.vertical, 9)  // 신호등 자리
            Rectangle().fill(Theme.hair).frame(height: 1)
            CaptionStreamView(lines: app.visibleLiveLines, compact: true)
                .padding(.horizontal, 12).padding(.vertical, 10)
            Rectangle().fill(Theme.hair).frame(height: 1)
            // 미니 컨트롤바 — §6 "글자 크기·배경 불투명도 상시 노출" 규약 충족 (2026-07-17 위원회 수정)
            HStack(spacing: 8) {
                Button { settings.fontScale = max(0.7, settings.fontScale - 0.1) } label: {
                    Text("A−").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink2).frame(width: 26, height: 22)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
                Text("\(Int(settings.fontScale * 100))%")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.ink3)
                Button { settings.fontScale = min(1.8, settings.fontScale + 0.1) } label: {
                    Text("A＋").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink2).frame(width: 26, height: 22)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
                Spacer()
                Text("배경").font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.ink3)
                Slider(value: $settings.opacity, in: 0.65...0.95)
                    .frame(width: 64).tint(Theme.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 300, idealWidth: 360, minHeight: 240, idealHeight: 320)
        .background(Color.black.opacity(settings.opacity))   // 딤은 배경만 — 텍스트는 항상 불투명
        .background(VisualEffectBackground())
        .background(WindowConfigurator())
        .background(WindowEventObserver(onModified: { app.popoutUserMoved = true }))  // 이동·리사이즈 시 자동 닫기 억제
        .onAppear { app.popoutOpen = true }
        .onDisappear {
            let wasAuto = app.popoutAutoShown
            app.popoutOpen = false
            app.popoutAutoShown = false
            app.popoutUserMoved = false
            // 자동으로 뜬 걸 '아직 뜰 조건'(녹음+가림+설정 켜짐)에서 닫았다 = 수동 닫기 → 세션 내 재표시 억제
            if wasAuto && app.sessionState == .recording && app.mainWindowOccluded && settings.autoShowPopout {
                app.popoutManuallyClosed = true
            }
        }
    }
}
#endif
