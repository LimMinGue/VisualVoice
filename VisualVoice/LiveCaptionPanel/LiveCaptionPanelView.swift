import SwiftUI

/// 자막 렌더 공용 컴포넌트 — 창 안 라이브 뷰와 팝아웃 패널이 함께 쓴다 (decisions.md §6).

struct CaptionStreamView: View {
    let lines: [CaptionLine]
    var compact: Bool = false

    // '새 자막' 배지 — 위로 스크롤해 읽는 중 새 확정 도착 알림 (decisions §8 · 목업 컨펌 2026-07-18)
    @State private var atBottom = true
    @State private var newCount = 0

    private var confirmedCount: Int { lines.reduce(0) { $0 + ($1.isVolatile ? 0 : 1) } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 11 : 15) {
                    ForEach(lines) { CaptionLineView(line: $0, compact: compact) }
                    Color.clear.frame(height: 1).id("vv-stream-bottom")   // 바닥 스크롤 앵커
                }
                .padding(.horizontal, compact ? 4 : 2)
                .padding(.vertical, 6)
                .frame(maxWidth: compact ? .infinity : 920, alignment: .leading)   // 행폭 캡 — 글자 상향(×1.3)에 비례 확대, 줄당 글자 수 유지 (WCAG 1.4.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)   // 새 자막 바닥 고정 — 위로 스크롤해 읽는 중엔 안 끌어내림 (2026-07-17 제작자 지시)
            // 바닥 근접 판정 — (바닥판정_여유) 40pt (QC: 실측 튜닝 여지)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 40
            } action: { _, near in
                atBottom = near
                if near { newCount = 0 }   // 바닥 복귀 → 배지 소멸·카운트 리셋
            }
            .onChange(of: confirmedCount) { old, new in
                if new > old, !atBottom { newCount += new - old }   // 떨어져 있을 때 온 확정만 계상
            }
            .overlay(alignment: .bottom) {
                if !atBottom, newCount > 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("vv-stream-bottom", anchor: .bottom) }
                        atBottom = true; newCount = 0
                    } label: {
                        HStack(spacing: 6) {
                            Text("새 자막 \(newCount)개")
                            Image(systemName: "arrow.down")
                        }
                        .font(.system(size: compact ? 11.5 : 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x062A30))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.accent, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, compact ? 8 : 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: newCount > 0 && !atBottom)
        }
    }
}

struct CaptionLineView: View {
    let line: CaptionLine
    var compact: Bool = false
    @EnvironmentObject var settings: PanelSettings
    @EnvironmentObject var app: AppModel
    @State private var showSpeakerMenu = false

    /// 단일 언어 세션(자막만)에선 번역 줄 자체가 없다 (decisions.md §2).
    private var showsTranslation: Bool {
        settings.showTranslation && !app.pair.isSingle && !line.translation.isEmpty
    }

    /// 내 잠정 줄은 확정 크기로 — 상대 잠정만 크게(주 정보), 내 잠정은 확인용 피드백(§12 화면 게이트 시각 위계 타협)
    private var enlargedVolatile: Bool { line.isVolatile && !(line.speaker == .me && !line.isTyped) }

    private var srcSize: CGFloat {
        (enlargedVolatile ? (compact ? 22 : 29) : (compact ? 20 : 26)) * settings.fontScale   // 일상 대화 기본 크기 상향 (2026-07-17 제작자 지시 2차)
    }
    private var trSize: CGFloat {
        (enlargedVolatile ? (compact ? 18 : 22) : (compact ? 17 : 21)) * settings.fontScale   // 일상 대화 기본 크기 상향 (2026-07-17 제작자 지시 2차)
    }

    /// 읽어주기 버튼 — 타이핑 발화(원문)·번역 줄 공용 (규칙 4: 반복 패턴 단일화)
    private func speakButton(text: String, langCode: String) -> some View {
        Button { SpeechOut.say(text, langCode: langCode) } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("읽어주기 — 재생 중에는 마이크 입력을 잠시 멈춥니다")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 화자 칩 탭 → 나로 지정 / 숨기기 (화자 분리 배정 라인만 — 워게임 확정 UX)
            Button {
                if line.fluidSpeaker != nil { showSpeakerMenu = true }
            } label: {
                SpeakerChip(speaker: line.speaker, uncertain: line.speakerUncertain, compact: compact)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSpeakerMenu, arrowEdge: .bottom) {
                if let idx = line.fluidSpeaker {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(line.speaker.label) · 트랙 \(idx)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button {
                            app.markSpeakerAsMe(idx); showSpeakerMenu = false
                        } label: { Label("이 화자를 '나'로 지정", systemImage: "person.fill.checkmark") }
                        Button {
                            app.toggleHideSpeaker(idx); showSpeakerMenu = false
                        } label: {
                            Label(app.hiddenSpeakerIndexes.contains(idx) ? "숨김 해제" : "이 화자 숨기기 (라디오·타인 음소거)",
                                  systemImage: app.hiddenSpeakerIndexes.contains(idx) ? "eye" : "eye.slash")
                        }
                        Text("숨겨도 녹취록에는 남습니다")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(minWidth: 230, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if line.isTyped {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                            .help("타이핑 발화")
                    }
                    // 치환 규칙은 확정 줄에만·렌더 시점에만(원문 불변 · 잠정 줄은 깜빡임 방지 — 2026-09-11 B⑤)
                    Text(line.isVolatile ? line.source : settings.display(line.source))
                        .font(.system(size: srcSize, weight: line.isVolatile ? .semibold : .regular))
                        .foregroundStyle(line.isVolatile ? Theme.ink : Theme.ink.opacity(0.75))   // 확정 톤 0.64→0.75 (AA 마진 확보)
                        .lineSpacing(compact ? 3 : 5)
                        .fixedSize(horizontal: false, vertical: true)
                    // 번역 줄이 있으면 읽어주기 버튼은 번역 줄 끝 하나로 통일(중복 UI 방지 — 규칙 4)
                    if line.isTyped, !showsTranslation {
                        speakButton(text: line.source, langCode: app.pair.a.code)
                    }
                }

                if showsTranslation {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(line.translation)
                            .font(.system(size: trSize))
                            .foregroundStyle(Theme.trans.opacity(line.isVolatile ? 1 : 0.78))   // 확정 번역 톤 상향(AA)
                            .lineSpacing(compact ? 2 : 4)
                            .fixedSize(horizontal: false, vertical: true)
                        // 번역문을 그 언어 음성으로 재생 — 상대가 들을 수 있게 (2026-07-17 제작자 지시)
                        speakButton(text: line.translation,
                                    langCode: TranslationCoordinator.detectLanguage(of: line.translation, between: app.pair))
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.trans.opacity(0.45)).frame(width: 2)
                    }
                }

                if line.isVolatile {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text("잠정 · 받아쓰는 중")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                } else if settings.density == .detailed {
                    Text(line.timecode)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.ink3)   // 알파 이중 감쇠 제거(3.01:1 → AA 통과 토큰)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(line.isVolatile ? 10 : 0)
        .background {
            if line.isVolatile {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.14), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.accent).frame(width: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct SpeakerChip: View {
    let speaker: Speaker
    var uncertain: Bool = false
    var compact: Bool = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(speaker.color).frame(width: 7, height: 7)
            Text(speaker.label)
                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            if uncertain {
                Text("?").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(speaker.color.opacity(0.85))
            }
        }
        .foregroundStyle(speaker.color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(speaker.color.opacity(0.16), in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                speaker.color.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: uncertain ? [3, 3] : [])
            )
        )
        .padding(.top, 2)
        // "클릭해 정정" 안내는 정정 팝오버 배선(로직 단계) 후에만 — 거짓 안내 금지(2026-07-17)
        .help(uncertain ? "화자 추정 불확실" : speaker.label)
    }
}

struct IconButton: View {
    let system: String
    var body: some View {
        Image(systemName: system)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink2)
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hair))
    }
}
