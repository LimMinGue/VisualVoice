import SwiftUI

/// 홈 — 언어 쌍·엔진 선택 + 캡처 모드 타일 + 최근 세션.
struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var pendingDelete: Session?
    @State private var hoveredRow: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("새 세션").font(.system(size: 19, weight: .bold))
                    Text(isPad ? "앞사람과의 대화를 자막으로" : "어떤 대화를 자막으로 볼까요?")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink3)
                }

                // 세션 종료 후 1회 고지(무자막 세션 등) — 무고지 홈 복귀 금지(2026-09-11). 다음 세션 시작 시 소멸.
                if let notice = app.homeNotice {
                    NoticeBanner(text: notice, color: Theme.warn, icon: "text.bubble", style: .card)
                }

                setupBar

                #if os(iOS)
                startConversationButton   // iPad = 마이크 전용 — 타일 그리드 대신 큰 시작 버튼
                #else
                // 2×2 고정 — 4개 타일의 공간 안정감 (2026-07-17)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(CaptureMode.allCases) { mode in captureTile(mode) }
                }
                #endif

                Text("최근 세션")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink3).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    if app.sessions.isEmpty {
                        // 첫 실행 — 예제 세션을 지어내지 않는다. 제목만 덩그러니 남지 않게 안내 한 줄.
                        Text("아직 저장된 세션이 없습니다. 위에서 대화를 시작하면 여기에 쌓입니다.")
                            .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(app.sessions.prefix(3))) { recentRow($0) }
                    }
                }
            }
            .padding(22)
        }
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

    // 세션 언어 — 언어 1·언어 2 드롭다운 2개. 같으면 자막만, 다르면 자막+번역 (2026-07-17).
    private var setupBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("대화 언어")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink2)

                langMenu("언어 1", selection: Binding(
                    get: { app.pair.a },
                    set: { app.pair = LanguagePair(a: $0, b: app.pair.b) }))
                langMenu("언어 2", selection: Binding(
                    get: { app.pair.b },
                    set: { app.pair = LanguagePair(a: app.pair.a, b: $0) }))

                // 모드 배지 — 선택 결과가 어떤 모드인지 즉시 피드백
                Text(app.pair.isSingle ? "자막만" : "자막 + 번역")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(app.pair.isSingle ? Theme.good : Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((app.pair.isSingle ? Theme.good : Theme.accent).opacity(0.13), in: Capsule())

                Spacer()

                HStack(spacing: 8) {
                    Text("엔진 자동").font(.system(size: 13, weight: .semibold))
                    // "ANE" 대신 "온디바이스"로 표기 통일(2026-07-17)
                    Text("온디바이스").font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hair))
            }
            Text(app.pair.isSingle
                 ? "같은 언어 대화 — 번역 없이 자막·녹취만 크게 보여드려요. (두 언어를 다르게 고르면 자동으로 번역이 켜집니다)"
                 : "두 언어 대화 — 발화마다 어느 언어인지 자동 감지해 상대 언어로 번역합니다.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hair))
    }

    private func langMenu(_ title: String, selection: Binding<AppLanguage>) -> some View {
        Menu {
            ForEach(AppLanguage.all) { lang in
                Button {
                    selection.wrappedValue = lang
                } label: {
                    if lang == selection.wrappedValue {
                        Label(lang.name, systemImage: "checkmark")
                    } else {
                        Text(lang.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink3)
                Text(selection.wrappedValue.name).font(.system(size: 13.5, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hair))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func captureTile(_ mode: CaptureMode) -> some View {
        // 스파이크 배선: 대면 대화(마이크)·온라인 미팅(시스템 오디오) 실동작. 나머지는 '다음 단계' 비활성.
        let wired = mode == .inPerson || mode == .onlineMeeting
        let bg: AnyShapeStyle = mode.isPrimary
            ? AnyShapeStyle(LinearGradient(colors: [Theme.accentDim, Theme.card],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Theme.card)
        return Button { app.start(mode) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.card2).frame(width: 34, height: 34)
                    Image(systemName: mode.symbol).foregroundStyle(Theme.accent).font(.system(size: 16))
                }
                Text(mode.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                Text(mode.desc).font(.system(size: 11.5)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(bg, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(mode.isPrimary ? Theme.accent.opacity(0.4) : Theme.hair))
            .opacity(wired ? 1 : 0.45)
            .overlay(alignment: .topTrailing) {
                if !wired {
                    Text("다음 단계")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Theme.hair))
                        .padding(12)
                }
                // ("Zoom 감지됨" 배지 제거 — 실제 감지 로직 배선 전까지 표시 안 함. 거짓 안내 금지)
            }
        }
        .buttonStyle(.plain)
    }

    /// iPad 분기 — 터치(호버 없음)·마이크 전용
    private var isPad: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    #if os(iOS)
    /// 캡처 타일 대신 큰 '대화 시작' 버튼 — iPad는 대면 대화(마이크) 전용.
    private var startConversationButton: some View {
        Button { app.start(.inPerson) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.card2).frame(width: 52, height: 52)
                    Image(systemName: "mic.fill").foregroundStyle(Theme.accent).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("대화 시작").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("마이크로 앞사람 말을 실시간 자막").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Text("시작")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x062A30))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .background(LinearGradient(colors: [Theme.accent.opacity(0.20), Theme.accent.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
    #endif

    private func recentRow(_ session: Session) -> some View {
        Button { app.openDetail(session) } label: { recentRowBody(session) }   // 진짜 Button — 접근성 API·VoiceOver 대응(2026-09-11)
            .buttonStyle(.plain)
            .accessibilityLabel("\(session.title), \(session.displayDate)")
            .contextMenu {
                Button("세션 상세 열기") { app.openDetail(session) }
                Divider()
                Button("삭제", role: .destructive) { pendingDelete = session }
            }
    }

    private func recentRowBody(_ session: Session) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.card2).frame(width: 30, height: 30)
                Image(systemName: "waveform").foregroundStyle(Theme.accent).font(.system(size: 13))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.system(size: 13.5, weight: .semibold))
                Text(session.preview).font(.system(size: 11.5)).foregroundStyle(Theme.ink3).lineLimit(1)
            }
            Spacer()
            // 자리 상시 예약 + 투명도 전환 — 호버 시 우측 메타가 밀리는 레이아웃 점프 제거(2026-07-17)
            Button { pendingDelete = session } label: {
                Image(systemName: "trash")
                    .font(.system(size: isPad ? 14 : 11, weight: .semibold))
                    .foregroundStyle(Theme.rec)
                    .frame(width: isPad ? 44 : 26, height: isPad ? 44 : 26)   // iPad 터치 타깃 44pt
                    .background(Theme.rec.opacity(0.12), in: RoundedRectangle(cornerRadius: isPad ? 10 : 7))
            }
            .buttonStyle(.plain)
            .help("세션 삭제")
            .opacity(isPad || hoveredRow == session.id ? 1 : 0)   // iPad: 호버 없음 — 상시 노출
            .allowsHitTesting(isPad || hoveredRow == session.id)
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.pairShort).font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 6))
                Text("\(session.displayDate) · \(session.duration)")
                    .font(.system(size: 11)).foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .background(hoveredRow == session.id ? Theme.card.opacity(0.6) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hoveredRow = $0 ? session.id : nil }
    }
}
