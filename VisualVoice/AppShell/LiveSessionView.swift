import SwiftUI
import Translation

/// 라이브 세션 — 본문 전체를 자막에. "패널로 띄우기"로 팝아웃.
struct LiveSessionView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var settings: PanelSettings
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var typedText = ""
    @State private var confirmStop = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let msg = app.statusMessage { NoticeBanner(text: msg, color: Theme.accent, icon: "hourglass") }
            // 온라인 미팅 조건부 배너 2종 — 스피커 이중 자막 경고 · 마이크 소프트 실패
            if app.speakerOutputActive, app.micCaptureOn, app.sessionState == .recording {
                NoticeBanner(text: "스피커로 소리가 나는 중 — 내 발화가 중복 기록될 수 있어요. 이어폰·에어팟 사용을 권장합니다.",
                             color: Theme.warn, icon: "speaker.wave.2")
            }
            if let micMsg = app.micBannerText { NoticeBanner(text: micMsg, color: Theme.accent, icon: "mic.slash") }
            // 녹음 저장 실패 — 녹음만 멈추고 자막은 계속(소프트 실패).
            if case .failed(let reason) = app.recordingStatus {
                NoticeBanner(text: "녹음이 중단되었습니다 — \(reason) 자막과 녹취는 계속 기록되고 있어요.",
                             color: Theme.warn, icon: "waveform.slash")
            }
            TranslationFailureBanner(translator: app.translator)   // 연속 실패·큐 버림만 — translator만 관찰
            SilenceBanner()   // metrics만 관찰 — 전체 재렌더 없음
            Rectangle().fill(Theme.hair).frame(height: 1)
            CaptionStreamView(lines: app.visibleLiveLines)
                .padding(.horizontal, 22).padding(.vertical, 14)
            Rectangle().fill(Theme.hair).frame(height: 1)
            typeBar
            Rectangle().fill(Theme.hair).frame(height: 1)
            controlBar
        }
        // 번역 세션 배선 — Translation framework 공식 경로(translationTask). 쌍의 두 방향 각각.
        .translationTask(app.translator.configAtoB) { session in await app.translator.drainAtoB(session) }
        .translationTask(app.translator.configBtoA) { session in await app.translator.drainBtoA(session) }
        .confirmationDialog("세션을 끝낼까요?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("끝내고 세션 상세 보기") { app.stopSession() }
            Button("계속 녹음", role: .cancel) {}
        } message: {
            Text("지금까지의 자막이 세션으로 저장되고 세션 상세로 이동합니다.")
        }
    }

    /// 세션 음원 녹음 상태 칩 — 소리로 확인할 수 없으므로 세션 내내 떠 있다.
    /// 빨강(Theme.rec)은 이미 '세션 녹음 중' 점이 쓰고 있어 회피 — 평상시 중립, 실패했을 때만 경고색.
    @ViewBuilder private var recordChip: some View {
        if app.sessionState == .recording || app.sessionState == .paused {
            let off = app.recordingStatus == .off
            let (text, color): (String, Color) = {
                switch app.recordingStatus {
                case .on:     return ("녹음 저장 중", Theme.ink2)
                case .off:    return ("녹음 저장 꺼짐", Theme.ink3)
                case .failed: return ("녹음 저장 실패", Theme.warn)
                }
            }()
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(off ? Color.clear : color)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: off ? 1.5 : 0))
                    .frame(width: 7, height: 7)
                Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(off ? Color.clear : color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(off ? Theme.hair : color.opacity(0.35)))
            .help(off ? "이 세션의 소리는 저장되지 않습니다 — 설정 > 녹음에서 켤 수 있어요"
                      : "대화 소리를 파일로 저장하는 중 — 세션을 삭제하면 녹음도 함께 지워집니다")
        }
    }

    /// 타이핑 발화 입력바 — 말하기 어려울 때 타이핑으로 대화에 참여.
    private var typeBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "keyboard")
                .font(.system(size: 13)).foregroundStyle(Theme.ink3)
            // 플레이스홀더 직접 렌더 — 시스템 기본 플레이스홀더는 다크 배경에서 안 보임
            ZStack(alignment: .leading) {
                if typedText.isEmpty {
                    Text(app.pair.isSingle
                         ? "타이핑으로 말하기 — 입력하면 대화 흐름에 추가됩니다 (Enter)"
                         : "타이핑으로 말하기 — 상대 언어로 번역되어 추가됩니다 (Enter)")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink3)
                        .allowsHitTesting(false)
                }
                TextField("", text: $typedText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .focused($inputFocused)
                    .onSubmit { submitTyped() }
            }
            Button { submitTyped() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(typedText.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Theme.ink3 : Theme.accent)
            }
            .buttonStyle(.plain)
            .help("대화에 추가")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.card.opacity(0.5))
    }

    private func submitTyped() {
        app.sendTyped(typedText)
        typedText = ""
        inputFocused = true   // 연속 입력 유지
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(app.liveTitle).font(.system(size: 16, weight: .bold))
            stateBadge
            LiveClock()        // 시계·미터·계기판 — metrics만 관찰하는 소형 뷰 (버벅임 수정)
            LiveMeter()
            LatencyBadge()
            Text(app.pair.label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(Capsule().stroke(Theme.hair))
            Spacer()

            // "내 마이크" 토글 — 온라인 미팅 전용
            if app.dualCaptureSession {
                Button { app.toggleMicCapture() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(app.micCaptureOn ? Theme.me : Theme.ink3).frame(width: 6, height: 6)
                        Text(app.micCaptureOn ? "내 마이크" : "내 마이크 꺼짐")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(app.micCaptureOn ? Theme.me : Theme.ink3)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background((app.micCaptureOn ? Theme.me.opacity(0.14) : Color.clear), in: Capsule())
                    .overlay(Capsule().stroke(app.micCaptureOn ? Theme.me.opacity(0.35) : Theme.hair))
                }.buttonStyle(.plain)
                .disabled(app.micBannerText != nil)   // 마이크 시작 실패 상태 — 토글 무의미(배너가 안내)
                .help(app.micCaptureOn
                      ? "내 발화를 자막·녹취에 담는 중 — 클릭하면 끕니다 (타이핑 발화는 계속 가능)"
                      : "내 마이크 꺼짐 — 내 발화가 기록되지 않습니다. 클릭하면 켭니다")
            }

            recordChip

            #if os(macOS)  // 팝아웃은 macOS 전용 — iPad 제외
            Button { openWindow(id: "caption-popout") } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pip.enter")
                    Text("패널로 띄우기")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35)))
            }.buttonStyle(.plain)
            #endif

            // 진짜 버튼 (구 IconButton 이미지 → 상태 머신 배선, 치명 결함 해소)
            Button { app.togglePause() } label: {
                Image(systemName: app.sessionState == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hair))
            }.buttonStyle(.plain)
            .disabled(app.sessionState == .idle || app.sessionState == .preparing)
            .help(app.sessionState == .paused ? "재개" : "일시정지")

            Button { confirmStop = true } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.rec)
                    .frame(width: 28, height: 28)
                    .background(Theme.rec.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
            .disabled(app.sessionState == .idle || app.sessionState == .preparing)
            .help("세션 끝내기 (확인 후 저장)")
        }
        .padding(.leading, 22).padding(.trailing, 16).padding(.top, 22).padding(.bottom, 12)
    }

    private var stateBadge: some View {
        let (color, label): (Color, String) = {
            switch app.sessionState {
            case .idle:      return (Theme.ink3, "대기")
            case .preparing: return (Theme.accent, "준비 중")
            case .recording: return (Theme.rec, "녹음 중")
            case .paused:    return (Theme.warn, "일시정지됨")
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11.5, weight: .bold, design: .rounded))
        }.foregroundStyle(color)
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                densityButton("간결", .simple)
                densityButton("상세", .detailed)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hair))

            HStack(spacing: 4) {
                fontButton("A−") { settings.fontScale = max(0.7, settings.fontScale - 0.1) }
                Text("\(Int(settings.fontScale * 100))%")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.ink3)
                fontButton("A＋") { settings.fontScale = min(1.8, settings.fontScale + 0.1) }
            }

            if !app.hiddenSpeakerIndexes.isEmpty {   // 숨긴 화자 표시기 — 복구 경로 상시 확보
                Button {
                    app.hiddenSpeakerIndexes.removeAll()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash").font(.system(size: 10))
                        Text("숨긴 화자 \(app.hiddenSpeakerIndexes.count) — 모두 해제")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .overlay(Capsule().stroke(Theme.hair))
                }.buttonStyle(.plain)
            }

            if !app.pair.isSingle {   // 단일 언어 세션(자막만)엔 번역 토글 자체가 없음
                Toggle("번역", isOn: $settings.showTranslation)
                    .toggleStyle(.button).tint(Theme.accent)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }

            Spacer()

            #if os(macOS)  // 배경 불투명도 = 팝아웃 전용 설정 — 팝아웃 없는 iPad에선 숨김(거짓 UI 금지)
            HStack(spacing: 7) {
                Text("배경").font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.ink2)
                    .help("팝아웃 패널의 배경 불투명도 — 자막 글자는 항상 선명하게 유지됩니다")
                Slider(value: $settings.opacity, in: 0.65...0.95).frame(width: 80).tint(Theme.accent)
            }
            #endif
            IconButton(system: "gearshape")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func densityButton(_ title: String, _ value: PanelSettings.Density) -> some View {
        let on = settings.density == value
        return Button { settings.density = value } label: {
            Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(on ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(on ? Theme.accentDim : Color.clear)
        }.buttonStyle(.plain)
    }

    private func fontButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink2)
                .frame(width: 30, height: 26)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hair))
        }.buttonStyle(.plain)
    }
}

// ── 고주파 신호 관찰 소형 뷰들 — AppModel이 아닌 LiveMetrics만 관찰해 이들만 재렌더 (2026-07-17 버벅임 수정) ──

/// 경과 시계
struct LiveClock: View {
    @EnvironmentObject var app: AppModel
    var body: some View { ClockText(metrics: app.metrics) }
    private struct ClockText: View {
        @ObservedObject var metrics: LiveMetrics
        var body: some View {
            Text(metrics.elapsedLabel).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.ink2)
        }
    }
}

/// 입력 레벨 미터 — "소리를 받고 있다"는 시각 신호. 칸 변화 시에만 갱신.
/// 온라인 미팅은 2계통(🎤 마이크 파랑 · 시스템 초록) — 어느 쪽이 죽었는지 즉시 보임.
struct LiveMeter: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        if app.dualCaptureSession {
            HStack(spacing: 9) {
                Bars(metrics: app.metrics, kind: .mic)
                Bars(metrics: app.metrics, kind: .system)
            }
        } else {
            Bars(metrics: app.metrics, kind: .single)
        }
    }
    private struct Bars: View {
        @ObservedObject var metrics: LiveMetrics
        var kind: Kind = .single
        enum Kind { case single, mic, system }
        private var step: Int { kind == .mic ? metrics.micMeterStep : metrics.meterStep }
        private var tint: Color { kind == .mic ? Theme.me : Theme.good }
        private var label: String {
            switch kind {
            case .single: return "마이크 입력 레벨"
            case .mic:    return "내 마이크 입력 레벨"
            case .system: return "시스템 오디오(상대 소리) 레벨"
            }
        }
        var body: some View {
            HStack(spacing: 3) {
                if kind == .mic { Image(systemName: "mic.fill").font(.system(size: 8)).foregroundStyle(Theme.ink3) }
                if kind == .system { Image(systemName: "display").font(.system(size: 8)).foregroundStyle(Theme.ink3) }
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule()
                            .fill(step > i
                                  ? (kind == .single ? (i >= 5 ? Theme.rec : Theme.good) : tint)
                                  : Color.white.opacity(0.10))
                            .frame(width: 3, height: 6 + CGFloat(i) * 1.6)
                    }
                }
            }
            .help(label)
            .accessibilityLabel(label)
        }
    }
}

/// 첫 자막 지연 실측 계기판
struct LatencyBadge: View {
    @EnvironmentObject var app: AppModel
    var body: some View { Badge(metrics: app.metrics) }
    private struct Badge: View {
        @ObservedObject var metrics: LiveMetrics
        var body: some View {
            if let d = metrics.firstCaptionDelay {
                Text(String(format: "첫 자막 +%.1f초", d))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(d <= 1.5 ? Theme.good : (d <= 3 ? Theme.warn : Theme.rec))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.hair))
                    .help("이번 세션에서 첫 말소리 감지부터 첫 자막 표출까지 걸린 시간 (실측 지표)")
            }
        }
    }
}

/// 실시간 번역 실패 배너 — 연속 3회 이상 또는 큐 상한 버림이 있을 때만(회복 시 자동 소멸). translator만 관찰.
struct TranslationFailureBanner: View {
    @ObservedObject var translator: TranslationCoordinator
    var body: some View {
        if let msg = translator.runtimeFailure {
            NoticeBanner(text: msg, color: Theme.warn, icon: "character.bubble")
        }
    }
}

/// 무음 경고 배너
struct SilenceBanner: View {
    @EnvironmentObject var app: AppModel
    var body: some View { Inner(app: app, metrics: app.metrics) }
    private struct Inner: View {
        let app: AppModel
        @ObservedObject var metrics: LiveMetrics
        var body: some View {
            if app.sessionState == .recording && metrics.silenceSeconds >= 15 {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash.fill").font(.system(size: 11, weight: .semibold))
                    Text("입력이 감지되지 않습니다 — 마이크가 켜져 있는지 확인하세요 (\(metrics.silenceSeconds)초째 무음)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.rec)
                .padding(.horizontal, 22).padding(.vertical, 7)
                .background(Theme.rec.opacity(0.10))
            }
        }
    }
}
