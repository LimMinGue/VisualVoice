import SwiftUI

/// 왼쪽 사이드바 — 이력 + 기능 이동 (decisions.md §5, SpectaLing·ALT 참조).
/// 사이드바 경과 시간 — metrics만 관찰 (사이드바 전체 재렌더 방지)
struct SidebarElapsed: View {
    @ObservedObject var metrics: LiveMetrics
    var body: some View {
        Text(metrics.elapsedLabel)
            .font(.system(size: 11, design: .monospaced)).opacity(0.8)
    }
}

struct SidebarView: View {
    @EnvironmentObject var app: AppModel
    @State private var pendingDelete: Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Theme.accent, Color(hex: 0x2F8FA6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Text("💬").font(.system(size: 14)))
                Text("VisualVoice").font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 4)

            Button { app.screen = .home } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text("새 세션")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x062B31))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // 라이브 이탈 시 상시 복귀 경로 — "녹음이 사라졌다" 착각 방지 (워게임 '치명' 해소)
            if app.sessionState != .idle && app.screen != .live {
                Button { app.screen = .live } label: {
                    HStack(spacing: 7) {
                        Circle().fill(app.sessionState == .paused ? Theme.warn : Theme.rec)
                            .frame(width: 8, height: 8)
                        Text(app.sessionState == .paused ? "일시정지됨 — 돌아가기" : "녹음 중 — 돌아가기")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                        SidebarElapsed(metrics: app.metrics)
                    }
                    .foregroundStyle(app.sessionState == .paused ? Theme.warn : Theme.rec)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background((app.sessionState == .paused ? Theme.warn : Theme.rec).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                navItem("홈", "house.fill", active: app.screen == .home) { app.screen = .home }
                navItem("기록 보관함", "tray.full.fill", active: app.screen == .archive) { app.screen = .archive }
                navItem("설정", "gearshape.fill", active: app.screen == .settings) { app.screen = .settings }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("최근 기록")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 8).padding(.top, 2)
                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                ForEach(app.sessions) { session in
                    // 진짜 Button — onTapGesture 행은 VoiceOver·접근성 API가 누를 수 없었다(2026-09-11 §15.3 a11y 대등→개선)
                    Button { app.openDetail(session) } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(session.dotColor).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Text("\(session.displayDate) · \(session.pairShort) · \(session.segments)구간 · \(session.duration)")
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.ink3).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(session.title), \(session.displayDate)")
                    .contextMenu {
                        Button("세션 상세 열기") { app.openDetail(session) }
                        Divider()
                        Button("삭제", role: .destructive) { pendingDelete = session }
                    }
                }
                }
                }
                .frame(maxHeight: 300)   // 세션 증가 시에도 하단 상태 pill 고정
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Theme.good).frame(width: 6, height: 6)
                    Text("온디바이스 · 오프라인")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.good)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.good.opacity(0.13), in: Capsule())
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(Theme.ink2)
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
        }
        .padding(12)
        .padding(.top, 22)   // 신호등 버튼 자리
        .frame(width: 250, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bgSide)
        .confirmationDialog("‘\(pendingDelete?.title ?? "")’ 세션을 삭제할까요?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let session = pendingDelete { app.delete(session) }
                pendingDelete = nil
            }
            Button("취소", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(app.deleteWarning(for: pendingDelete))
        }
    }

    private func navItem(_ title: String, _ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Theme.ink : Theme.ink2)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(active ? Theme.accentDim : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
