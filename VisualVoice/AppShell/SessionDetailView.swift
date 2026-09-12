import SwiftUI

/// 세션 상세 — 끝난 세션의 녹취록·회의록·내보내기.
/// 회의록은 여기의 "회의록" 탭에서 확인한다.
struct SessionDetailView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var settings: PanelSettings
    @State private var tab: Tab = .transcript
    @State private var confirmDelete = false
    @State private var jumpTargetID: UUID?   // 근거 타임코드 칩 → 녹취록 해당 발화 점프·강조
    @State private var showExport = false    // 내보내기 시트
    @State private var editingTitle = false  // 제목 인라인 편집 — 기록 보관함에서 연 세션도 수정 가능
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var editingParticipant: String?   // 정정 중인 참여자(speakerLabel), nil=표시 (2026-07-18)
    @State private var participantDraft = ""
    @FocusState private var participantFocused: Bool
    @State private var showRefined = true            // AI 재번역 토글 — 기본=AI 재번역
    @State private var hoveredLine: UUID?            // 호버 줄 — 원래 실시간 번역 취소선 노출
    @State private var recordings: [SessionRecorder.Item] = []   // 세션 음원 — 세션 전환 시에만 디스크 조회
    @State private var speakerMenuLine: UUID?        // 화자 재지정 팝오버가 열린 줄
    @State private var reassignWholeTrack = false    // 같은 분리 트랙의 모든 줄에 적용
    @State private var confirmRegenerate = false     // 회의록 다시 만들기 확인(.ready에서만 — 덮어쓰기 확인)

    enum Tab: String, CaseIterable {
        case transcript = "녹취록"
        case minutes = "회의록"
        case retranscript = "재전사 대본"   // 녹음 재전사 결과가 있을 때만 노출 — 빈 탭을 만들지 않는다
    }
    private var visibleTabs: [Tab] {
        Tab.allCases.filter { $0 != .retranscript || app.selectedSession?.retranscript != nil }
    }

    var body: some View {
        let session = app.selectedSession
        VStack(spacing: 0) {
            header(session)
            Rectangle().fill(Theme.hair).frame(height: 1)
            tabBar
            recordingSection
            notesSection(session)
            Group {
                switch tab {
                case .transcript: transcript
                case .minutes: minutes
                case .retranscript: retranscriptView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(session: session)
        }
        // 세션 전환 시 편집 상태 초기화 — 편집 도중 다른 세션을 열면 초안이 남아 엉뚱한 세션의 동일
        // 화자에 커밋되던 문제 차단(검증 확증). 제목 편집 잔존도 함께 해소.
        .onChange(of: app.selectedSession?.id) { _, _ in
            editingParticipant = nil; participantDraft = ""; editingTitle = false
            speakerMenuLine = nil; jumpTargetID = nil   // 팝오버·점프 상태도 세션 간 누수 금지
        }
        .confirmationDialog("회의록을 다시 만들까요?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("다시 만들기") { if let id = session?.id { app.regenerateMinutes(sid: id) } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("요약·결정·할 일이 새로 생성됩니다. 직접 정정한 참여 인원 이름은 그대로 유지됩니다.")
        }
        .task(id: app.selectedSession?.id) {
            recordings = app.selectedSession.map { SessionRecorder.items(for: $0.id) } ?? []
        }
        .confirmationDialog("이 세션을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let session { app.delete(session) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(app.deleteWarning(for: session))
        }
    }

    /// 세션 음원 — 녹음이 없으면 **행 자체가 없다**(비활성 버튼·'없음' 표기 금지).
    /// 녹음 기능 이전에 만들어진 세션이 자연스럽게 이 경우에 해당한다.
    @ViewBuilder private var recordingSection: some View {
        if !recordings.isEmpty {
            let total = recordings.reduce(Int64(0)) { $0 + $1.bytes }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 16)).foregroundStyle(Theme.ink2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("녹음 파일 \(recordings.count)개 · \(SessionRecorder.sizeLabel(total))")
                            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(recordings.contains { $0.stream == .system }
                             ? "시스템 소리와 내 마이크를 각각 원음·인식 음원으로 저장했습니다."
                             : "마이크 소리를 원음·인식 음원으로 저장했습니다.")
                            .font(.system(size: 11)).foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    #if os(macOS)
                    FinderRevealButton(urls: recordings.map(\.url))
                    #endif
                }
                ForEach(recordings) { item in
                    HStack(spacing: 8) {
                        Text(item.kind.label)
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(item.kind == .raw ? Theme.ink2 : Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((item.kind == .raw ? Theme.ink2 : Theme.accent).opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 5))
                        Text(item.url.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.ink3).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(item.sizeLabel)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.ink3)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                }
                batchActions
            }
            .padding(.horizontal, 22).padding(.vertical, 13)
            Rectangle().fill(Theme.hair).frame(height: 1)
        }
    }

    /// 종료 후 배치 작업 — 화자 다시 인식 · 녹음 재전사. 녹음이 있는 세션에서만(위 섹션 안).
    /// 세션 진행 중·다른 배치 진행 중엔 비활성(공유 Whisper 파이프 경쟁 보호). 한계는 미리 고백한다.
    @ViewBuilder private var batchActions: some View {
        let sid = app.selectedSession?.id
        if let p = app.batchProgress {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(p.total > 0 ? "\(p.label) \(p.done)/\(p.total)" : p.label)
                    .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                Spacer()
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 10) {
                Menu {
                    Button("인원 자동 추정") { if let sid { app.recomputeSpeakers(sid: sid, numSpeakers: nil) } }
                    ForEach(2...5, id: \.self) { n in
                        Button("\(n)명으로") { if let sid { app.recomputeSpeakers(sid: sid, numSpeakers: n) } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.wave.2")
                        Text("화자 다시 인식")
                    }
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.35)))
                }
                .menuStyle(.button).buttonStyle(.plain).fixedSize()
                .disabled(!app.canRunBatch)
                .help("녹음 원음으로 화자를 다시 나눕니다(온디바이스 · 최초 1회 모델 다운로드). 직접 지정한 화자는 그대로 둡니다")

                Button { if let sid { app.retranscribe(sid: sid) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                        Text(app.selectedSession?.retranscript == nil ? "이 녹음 다시 전사" : "다시 전사")
                    }
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(!app.canRunBatch)
                .help("녹음 전체를 게이트 없이 통째로 전사해 '재전사 대본' 탭에 보여줍니다 — 라이브 자막이 놓친 말을 대조하는 용도")
                Spacer()
            }
            .padding(.top, 4)
            Text(app.sessionState != .idle
                 ? "세션이 진행 중일 때는 실행할 수 없어요 — 실시간 자막을 느리게 만듭니다."
                 : "화자 구분은 목소리가 뚜렷이 다르고 마이크가 가까울수록 정확합니다. 멀리서 녹음하면 여러 사람이 한 화자로 묶일 수 있어요.")
                .font(.system(size: 11)).foregroundStyle(Theme.ink3)
        }
        if let err = app.batchError {
            NoticeBanner(text: err, color: Theme.warn, icon: "exclamationmark.triangle", style: .card)
        }
    }

    /// 재전사 대본 탭 — 녹음 통짜 전사(정답 대본 후보). 라이브 자막과 줄 수·내용을 눈으로 대조한다.
    private var retranscriptView: some View {
        let session = app.selectedSession
        let lines = session?.retranscript ?? []
        let liveCount = session?.transcript?.count ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session?.retranscriptInfo ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                    Text("라이브 자막 \(liveCount)줄 · 재전사 \(lines.count)줄 — 재전사는 게이트·잠정 없이 파일을 통째로 읽은 결과라 라이브가 놓친 말이 여기 남습니다. 원래 녹취록은 바뀌지 않습니다.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(line.timecode)
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.ink3).padding(.top, 4)
                        if line.speaker != .unlabeled { SpeakerChip(speaker: line.speaker) }
                        Text(settings.display(line.source))
                            .font(.system(size: 15 * settings.fontScale)).foregroundStyle(Theme.ink)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                }
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    /// 세션 기록 조건 — 세션 중 열화 사유(마이크 실패·오디오 끊김·녹음 실패·번역 실패)와 구 세션 날짜 안내.
    /// 라이브 배너로만 스쳐가던 정보를 기록에 남긴다(정직 표기 원칙). 없으면 행 자체가 없다.
    @ViewBuilder private func notesSection(_ session: Session?) -> some View {
        let notes = session?.notes ?? []
        let legacy = session?.isLegacyUndated ?? false
        if !notes.isEmpty || legacy {
            VStack(alignment: .leading, spacing: 6) {
                if legacy {
                    Text("이 세션은 날짜 기록 기능(2026-09-11) 이전에 만들어져 실제 날짜를 알 수 없습니다.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                }
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(Theme.warn).padding(.top, 2)
                        Text(note).font(.system(size: 12)).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 11)
            Rectangle().fill(Theme.hair).frame(height: 1)
        }
    }

    private func commitTitle(_ session: Session?) {
        if let id = session?.id { app.renameSession(id, to: titleDraft) }   // 빈값이면 renameSession이 무시
        editingTitle = false
    }

    private func header(_ session: Session?) -> some View {
        HStack(spacing: 10) {
            Button { app.screen = app.detailReturn } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 26, height: 26)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if editingTitle {
                    TextField("세션 이름", text: $titleDraft)
                        .textFieldStyle(.plain).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink).frame(maxWidth: 340)
                        .focused($titleFocused)
                        .onSubmit { commitTitle(session) }
                        .onExitCancel { editingTitle = false }   // Esc = 취소(원복 · macOS)
                        .onAppear { titleFocused = true }
                } else {
                    Button {
                        titleDraft = session?.title ?? ""; editingTitle = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(session?.title ?? "세션").font(.system(size: 16, weight: .bold))
                            Image(systemName: "pencil").font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                        }
                    }.buttonStyle(.plain).help("클릭해 이름 변경")
                }
                Text("\(session?.displayDate ?? "") · \(session?.pairShort ?? "") · \(session?.segments ?? 0)구간 · \(session?.duration ?? "")"
                     + (session?.engineLabel.map { " · \($0)" } ?? ""))   // 어느 인식기였는지 — 사후 분석 시 판별용
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            }
            Spacer()

            Button { showExport = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                    Text("내보내기")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35)))
            }.buttonStyle(.plain)
            .help("TXT · Markdown · PDF · DOCX · JSON")

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.rec)
                    .frame(width: 28, height: 28)
                    .background(Theme.rec.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            .help("세션 삭제")
        }
        .padding(.leading, 22).padding(.trailing, 16).padding(.top, 22).padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(tab == t ? Theme.ink : Theme.ink2)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(tab == t ? Theme.accentDim : Color.clear)
                        .overlay(alignment: .bottom) {
                            if tab == t { Rectangle().fill(Theme.accent).frame(height: 2) }
                        }
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }

    // AI 재번역 상태 바 — 진행(n/N·취소)/실패 배너/완료 토글
    @ViewBuilder private func retransBar(_ session: Session?) -> some View {
        switch session?.refinement {
        case .refining:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(app.retransProgress.map { "AI 재번역 중… \($0.done)/\($0.total)" } ?? "AI 재번역 중…")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                Spacer()
                Button("취소") { app.cancelRetranslation() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hair))
            }
            .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hair))
            .padding(.horizontal, 22).padding(.top, 14)
        case .unavailable(let msg):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                Text(msg).font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                Spacer(minLength: 0)
            }
            .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hair))
            .padding(.horizontal, 22).padding(.top, 14)
        case .ready:
            // 부분 실패 N/M — 스키마 손대지 않고 녹취록에서 파생. 취소한 경우도 같은 수치가 정직하다.
            let lines = session?.transcript ?? []
            let total = lines.filter { !$0.source.isEmpty }.count
            let missing = total - lines.filter { $0.refinedTranslation != nil }.count
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        segButton("AI 재번역", on: showRefined) { showRefined = true }
                        segButton("실시간 번역", on: !showRefined) { showRefined = false }
                    }
                    .padding(2)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hair))
                    Text("✦ = AI가 다시 번역한 줄 · 줄에 마우스를 올리면 원래 번역 확인")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                    Spacer()
                }
                if missing > 0 {
                    Text("\(total)줄 중 \(missing)줄은 AI 재번역을 만들지 못했습니다 — 그 줄은 실시간 번역을 표시하고 있어요.")
                        .font(.system(size: 11)).foregroundStyle(Theme.warn)
                }
            }
            .padding(.horizontal, 22).padding(.top, 14)
        case nil:
            EmptyView()
        }
    }

    private func segButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(on ? Theme.accent : Theme.ink3)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(on ? Theme.accentDim : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    // 녹취록 — 타임코드·화자 라벨 전체 표기 (상세 밀도). 근거 칩 점프 시 해당 발화로 스크롤·강조.
    private var transcript: some View {
        VStack(spacing: 0) {
            retransBar(app.selectedSession)
            transcriptScroll
        }
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(app.selectedSession?.transcript ?? CaptionLine.sampleTranscript) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Text(line.timecode)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.ink3)
                                .padding(.top, 4)
                            // 화자 칩 탭 → 재지정 팝오버 — 저장 뒤에도 화자를 고칠 수 있는 유일한 경로(정정 UX 필수)
                            Button { reassignWholeTrack = false; speakerMenuLine = line.id } label: {
                                SpeakerChip(speaker: line.speaker, uncertain: line.speakerUncertain)
                            }
                            .buttonStyle(.plain)
                            .help("클릭해 화자 바꾸기")
                            .popover(isPresented: Binding(get: { speakerMenuLine == line.id },
                                                          set: { if !$0 { speakerMenuLine = nil } }),
                                     arrowEdge: .bottom) { speakerMenu(line) }
                            VStack(alignment: .leading, spacing: 4) {
                                let shown = settings.display(line.source)   // 치환 규칙 — 표시만, 원문은 help로
                                Text(shown)
                                    .font(.system(size: 15 * settings.fontScale))   // 글자 크기 설정을 녹취록에도 일관 적용
                                    .foregroundStyle(Theme.ink)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .help(shown == line.source ? "" : "원문: \(line.source)")
                                if showRefined, let refined = line.refinedTranslation {
                                    // AI 재번역 줄 — 청록 보더 + ✦ 미세 마커(줄 배지 없음 — '추정' 배지 철회 선례)
                                    (Text(refined) + Text("  ✦").font(.system(size: 9)))
                                        .font(.system(size: 12.5 * settings.fontScale))
                                        .foregroundStyle(Theme.accent.opacity(0.9))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 12)
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(Theme.accent.opacity(0.55)).frame(width: 2)
                                        }
                                    if hoveredLine == line.id, !line.translation.isEmpty {
                                        Text(line.translation)   // 호버 — 원래 실시간 번역(취소선·정직 대조)
                                            .strikethrough(color: Theme.ink3.opacity(0.5))
                                            .font(.system(size: 11 * settings.fontScale))
                                            .foregroundStyle(Theme.ink3)
                                            .padding(.leading, 12)
                                    }
                                } else if !line.translation.isEmpty {   // 단일 언어 세션 — 빈 번역 줄 잔재 제거
                                    Text(line.translation)
                                        .font(.system(size: 12.5 * settings.fontScale))
                                        .foregroundStyle(Theme.trans.opacity(0.8))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 12)
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(Theme.trans.opacity(0.4)).frame(width: 2)
                                        }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(jumpTargetID == line.id ? Theme.accentDim : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))   // 점프 도착 발화 강조
                        .onHover { inside in
                            if inside { hoveredLine = line.id }
                            else if hoveredLine == line.id { hoveredLine = nil }
                        }
                        .id(line.id)
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)   // 행폭 캡 — 회의록 탭과 리듬 통일
            }
            .onAppear {   // 회의록 탭에서 칩을 눌러 넘어온 직후 — 뷰 생성 시점에 스크롤
                if let target = jumpTargetID { proxy.scrollTo(target, anchor: .center) }
            }
            .onChange(of: jumpTargetID) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .center) } }
            }
        }
    }

    /// 화자 재지정 팝오버 — 나 · 기존 상대 N · 새 상대. 트랙이 있는 줄은 '같은 화자 전부' 토글.
    private func speakerMenu(_ line: CaptionLine) -> some View {
        let lines = app.selectedSession?.transcript ?? []
        let remotes = Set(lines.compactMap { l -> Int? in if case .remote(let n) = l.speaker { return n } else { return nil } })
        let options: [Speaker] = [.me] + remotes.sorted().map { .remote($0) } + [.remote((remotes.max() ?? 0) + 1)]
        return VStack(alignment: .leading, spacing: 8) {
            Text("화자 바꾸기").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            ForEach(options, id: \.self) { sp in
                Button {
                    app.reassignSpeaker(lineID: line.id, to: sp, wholeTrack: reassignWholeTrack)
                    speakerMenuLine = nil
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(sp.color).frame(width: 7, height: 7)
                        Text(sp.label + (sp == line.speaker ? " (현재)" : (remotes.contains(where: { .remote($0) == sp }) || sp == .me ? "" : " (새 화자)")))
                    }
                }
                .disabled(sp == line.speaker && !reassignWholeTrack)
            }
            if let track = line.fluidSpeaker {
                Divider()
                Toggle("같은 화자(트랙 \(track))의 모든 줄에 적용", isOn: $reassignWholeTrack)
                    .font(.system(size: 11))
            }
            Text("녹취록 문장은 바뀌지 않습니다 · 직접 지정한 화자는 자동 재계산이 덮지 않아요")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(minWidth: 260, alignment: .leading)
    }

    /// 회의록 다시 만들기 버튼 — 재번역 진행 중엔 비활성(Gemma+FM 동시 상주 금지)
    private func regenerateButton(_ session: Session?, confirm: Bool) -> some View {
        Button {
            if confirm { confirmRegenerate = true } else if let id = session?.id { app.regenerateMinutes(sid: id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text("회의록 다시 만들기")
            }
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(session?.refinement == .refining || (session?.transcript ?? []).isEmpty)
        .help(session?.refinement == .refining ? "AI 재번역이 끝난 뒤 다시 만들 수 있어요" : "온디바이스 AI로 회의록을 새로 작성합니다")
    }

    // 회의록 — 세션 정지 시 온디바이스 AI가 자동 작성.
    // 참여 인원은 대화에서 추측 가능하면 자동 기록한다.
    private var minutes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch app.selectedSession?.minutes ?? .none {
                case .none:
                    noticeCard("이 세션에는 회의록이 없습니다. 발화가 기록된 세션을 정지하면 온디바이스 AI가 자동 작성합니다.")
                case .generating:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("회의록 작성 중… (온디바이스)")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hair))
                case .unavailable(let msg):
                    noticeCard(msg)
                    regenerateButton(app.selectedSession, confirm: false)   // 실패·미가용 상태의 유일한 재시도 경로
                case .ready(let m):
                    if !m.participants.isEmpty {
                        minutesCard("참여 인원", icon: "person.2") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(m.participants, id: \.speakerLabel) { p in
                                    participantRow(p)
                                }
                            }
                        }
                    }
                    minutesCard("요약", icon: "text.alignleft") {
                        Text(m.summary)
                            .font(.system(size: 13.5)).foregroundStyle(Theme.ink).lineSpacing(4)
                    }
                    if !m.decisions.isEmpty {
                        minutesCard("핵심 결정", icon: "checkmark.seal") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(m.decisions.enumerated()), id: \.offset) { _, d in
                                    bullet(d.text, sources: d.sourceTimecodes)
                                }
                            }
                        }
                    }
                    if !m.actionItems.isEmpty {
                        minutesCard("할 일", icon: "checklist") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(m.actionItems.enumerated()), id: \.offset) { _, t in
                                    todo(t.text, who: t.who.isEmpty ? "미정" : t.who, sources: t.sourceTimecodes)
                                }
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text("회의록은 온디바이스 AI가 자동 작성했습니다. 타임코드 칩은 근거 발화 위치, '확인 필요'는 근거를 찾지 못한 항목입니다.")
                            .font(.system(size: 11)).foregroundStyle(Theme.ink3)
                        Spacer(minLength: 0)
                        regenerateButton(app.selectedSession, confirm: true)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(22)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5)).foregroundStyle(Theme.ink2).lineSpacing(3)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hair))
    }

    /// 근거 타임코드 칩 점프 — 녹취록 탭으로 전환해 해당 발화를 강조 (청각으로 재검증할 수 없는 사용자의 검증 경로)
    private func jump(to timecode: String) {
        guard let line = app.selectedSession?.transcript?.first(where: { $0.timecode == timecode }) else { return }
        jumpTargetID = line.id
        tab = .transcript
    }

    private func speakerFromLabel(_ label: String) -> Speaker {
        if label == "나" { return .me }
        if label.hasPrefix("상대"),
           let n = Int(label.dropFirst(2).trimmingCharacters(in: .whitespaces)) { return .remote(n) }
        return .unlabeled
    }

    private func minutesCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.accent).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hair))
    }

    private func bullet(_ text: String, sources: [String] = [], needsCheck: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.ink)
            trustMarks(sources: sources, needsCheck: needsCheck)
        }
    }

    /// 신뢰도 표기 — 근거 타임코드 칩(탭=녹취록 근거 발화로 이동 · 로직 후속) + '확인 필요' 배지.
    /// 규약: 근거 타임코드가 없는 항목은 자동으로 '확인 필요' — LLM이 근거 없이 만든 항목의 방어선.
    @ViewBuilder
    private func trustMarks(sources: [String], needsCheck: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(sources.prefix(2), id: \.self) { tc in
                Button { jump(to: tc) } label: {
                    Text(tc)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.card2, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("근거 발화 \(tc) — 누르면 녹취록으로 이동합니다")
            }
            if sources.count > 2 {
                Text("+\(sources.count - 2)")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.ink3)
            }
            if needsCheck || sources.isEmpty {
                Text("확인 필요")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.rec)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Theme.rec.opacity(0.5),
                                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .help("근거 발화를 찾지 못한 항목입니다 — 녹취록에서 직접 확인하세요")
            }
        }
        .padding(.top, 1)
    }

    /// 참여 인원 한 줄 — 화자 칩 + 이름(정정 가능). 배지 없음:
    /// 이름을 못 맞힌 자리는 추정값(역할)을 기울임으로 시드해 보여주고, 클릭하면 인라인 편집
    /// (세션 제목 편집과 같은 패턴). 정정하면 그 이름으로 저장, 별도 확정 표시 없음.
    @ViewBuilder
    private func participantRow(_ p: MeetingMinutes.Participant) -> some View {
        HStack(spacing: 9) {
            SpeakerChip(speaker: speakerFromLabel(p.speakerLabel))
            if editingParticipant == p.speakerLabel {
                // 미상 자리는 빈값으로 시드(placeholder에 추정 역할을 힌트로) → 무수정 Enter 시 역할이 이름으로
                // 굳거나 중복 표기되는 문제 차단(검증 확증). 이름을 맞힌 자리는 그 이름으로 시드해 제자리 수정.
                TextField(p.hasKnownName ? "이름" : p.displayName, text: $participantDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: 200)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent))
                    .focused($participantFocused)
                    .onSubmit { commitParticipant(p) }
                    .onExitCancel { editingParticipant = nil }   // Esc = 취소(원복 · macOS)
                    .onAppear { participantFocused = true }
            } else {
                Button {
                    participantDraft = p.hasKnownName ? p.name : ""   // 미상=빈값 시드(힌트는 placeholder)
                    editingParticipant = p.speakerLabel
                } label: {
                    HStack(spacing: 6) {
                        Text(p.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.hasKnownName ? Theme.ink : Theme.ink2)   // 추정 시드는 낮은 톤
                            .italic(!p.hasKnownName)
                        Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain).help("클릭해 이름 정정")
                if p.showsDetailSuffix {
                    Text("· \(p.detail)").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func commitParticipant(_ p: MeetingMinutes.Participant) {
        app.renameParticipant(speakerLabel: p.speakerLabel, to: participantDraft)   // 빈 이름은 renameParticipant가 무시
        editingParticipant = nil
    }

    private func todo(_ text: String, who: String, sources: [String] = [], needsCheck: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square").foregroundStyle(Theme.ink3).font(.system(size: 12)).padding(.top, 2)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.ink)
            Text(who).font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.card2, in: Capsule())
            trustMarks(sources: sources, needsCheck: needsCheck)
        }
    }
}

/// 내보내기 시트 — 형식 4종 + 포함 옵션(토글 3종 + 회의록).
struct ExportSheet: View {
    let session: Session?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: PanelSettings   // 치환 규칙 — 화면과 같은 값이 문서에도

    @State private var format: ExportFormat = .md
    @State private var includeTimecode = true
    @State private var includeSpeaker = true
    @State private var includeTranslation = true
    @State private var includeMinutes = true
    @State private var useRefined = true   // 번역 = AI 재번역 우선(기본 ON)
    @State private var includeTranscript = true   // 끄면 회의록만 한 장으로
    @State private var removeFillers = false      // 군말 제거 — 내보내기 전용·기본 OFF

    private var hasMinutes: Bool {
        if case .ready = session?.minutes ?? .none { return true }
        return false
    }
    /// 회의록·녹취록을 둘 다 끄면 빈 문서 — 2026-07-18 DOCX 결함과 같은 지점이라 시트에서 차단
    private var hasContent: Bool { includeTranscript || (includeMinutes && hasMinutes) }

    private var hasRefined: Bool {
        session?.transcript?.contains { $0.refinedTranslation != nil } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("내보내기")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("형식").font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink3)
                HStack(spacing: 8) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Button { if f.ready { format = f } } label: {
                            HStack(spacing: 5) {
                                Text(f.rawValue).font(.system(size: 12, weight: .semibold, design: .rounded))
                                if !f.ready {
                                    Text("준비 중").font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .foregroundStyle(format == f ? Theme.accent : (f.ready ? Theme.ink2 : Theme.ink3))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(format == f ? Theme.accentDim : Theme.card2,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(format == f ? Theme.accent.opacity(0.4) : Theme.hair))
                        }
                        .buttonStyle(.plain)
                        .help(f.ready ? "" : "DOCX 내보내기는 준비 중입니다")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("포함 옵션").font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink3)
                Toggle("타임코드", isOn: $includeTimecode)
                Toggle("화자 라벨", isOn: $includeSpeaker)
                Toggle("원문·번역 이중 표기", isOn: $includeTranslation)
                Toggle("회의록 포함", isOn: $includeMinutes)
                    .disabled(!hasMinutes)
                if !hasMinutes {
                    Text("이 세션에는 회의록이 없어 녹취록만 내보냅니다.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                }
                Toggle("번역을 AI 재번역으로", isOn: $useRefined)
                    .disabled(!hasRefined)
                if hasRefined && useRefined {
                    Text("파일에 'AI 재번역' 표기와 ✦ 마커가 함께 들어갑니다.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                }
                Toggle("녹취록 포함", isOn: $includeTranscript)
                    .disabled(!(includeMinutes && hasMinutes))   // 회의록이 없으면 녹취록을 끌 수 없다(빈 문서 차단)
                Toggle("군말 제거 (음·어·저기·um·uh)", isOn: $removeFillers)
                    .disabled(!includeTranscript)
                if removeFillers && includeTranscript {
                    Text("파일에서만 지웁니다 — 저장된 녹취록과 화면은 그대로입니다. 인니어는 anu·eee만 처리합니다.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                }
                if !settings.replaceRules.isEmpty {
                    Text("치환 규칙 \(settings.replaceRules.count)개가 화면과 같게 적용됩니다.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                }
            }
            .toggleStyle(.switch)
            .font(.system(size: 12.5))

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                Button {
                    if let session {
                        SessionExporter.run(session: session, format: format,
                                            options: .init(includeTimecode: includeTimecode,
                                                           includeSpeaker: includeSpeaker,
                                                           includeTranslation: includeTranslation,
                                                           includeMinutes: includeMinutes && hasMinutes,
                                                           useRefined: useRefined && hasRefined,
                                                           includeTranscript: includeTranscript,
                                                           removeFillers: removeFillers,
                                                           replaceRules: settings.replaceRules))
                    }
                    dismiss()
                } label: {
                    Text("내보내기")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(hasContent ? Theme.accent : Theme.ink3)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(hasContent ? Theme.accentDim : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(hasContent ? Theme.accent.opacity(0.4) : Theme.hair))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(Theme.bgMain)
    }
}

/// Esc 취소 — onExitCommand는 macOS 전용. iPad는 미배선(Enter 저장·빈값 무시 경로만 쓰는 최소 적응).
private extension View {
    @ViewBuilder
    func onExitCancel(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
