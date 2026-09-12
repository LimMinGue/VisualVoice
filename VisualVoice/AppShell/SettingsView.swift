import SwiftUI

/// 설정 화면 — 기존 PanelSettings 표면화 + 영속화.
/// v1 범위: 표시(밀도·글자크기·불투명도·이중표기) + 자막 패널(창 가림 자동표시).
/// 고대비·엔진 오버라이드·언어팩은 백엔드 필요한 별도 후속 — 가짜 행 금지(거짓 안내 방지).
struct SettingsView: View {
    @EnvironmentObject var settings: PanelSettings
    @State private var recordingBytes: Int64 = 0   // 디렉터리 조회 1회 — 매 렌더가 아니라 화면 진입 시
    @State private var newFrom = ""                // 치환 규칙 추가 행
    @State private var newTo = ""
    @State private var newWholeWord = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("설정").font(.system(size: 22, weight: .bold))

                group("표시") {
                    row("밀도", "간결=현재 발화 위주 · 상세=타임코드·이력 포함") {
                        Picker("", selection: $settings.density) {
                            Text("간결").tag(PanelSettings.Density.simple)
                            Text("상세").tag(PanelSettings.Density.detailed)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    }
                    divider
                    row("글자 크기", "70% ~ 180% (팝아웃 패널에도 상시 노출)") {
                        HStack(spacing: 8) {
                            stepBtn("A−") { settings.fontScale = max(0.7, settings.fontScale - 0.1) }
                            Text("\(Int((settings.fontScale * 100).rounded()))%")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink2)
                                .frame(width: 44)
                            stepBtn("A＋") { settings.fontScale = min(1.8, settings.fontScale + 0.1) }
                        }
                    }
                    divider
                    row("배경 불투명도", "팝아웃 배경 딤 — 자막 글자는 항상 선명") {
                        Slider(value: $settings.opacity, in: 0.65...0.95).frame(width: 140).tint(Theme.accent)
                    }
                    divider
                    row("원문 + 번역 이중 표기", "번역 세션에서 원문 아래 번역 병기 (단일 언어 세션엔 없음)") {
                        Toggle("", isOn: $settings.showTranslation).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                }

                group("자막 패널") {
                    row("창 가림 시 자막 패널 자동 표시", "메인 창이 가려지거나 최소화되면 자막을 항상-위 패널로 자동 전환합니다") {
                        Toggle("", isOn: $settings.autoShowPopout).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                }

                // LocalAgreement — 회귀 테스트 합격(04 무회귀·05 무갭 1줄→4줄) 후 실사용 판정용 실험 토글.
                group("인식 (실험)") {
                    row("쉼 없이 이어지는 말을 문장 단위로 먼저 확정",
                        "두 사람이 쉼 없이 주고받을 때 앞 문장을 먼저 확정해 한 줄로 뭉치거나 언어가 섞이는 것을 줄입니다. 인도네시아어(Whisper) 경로에만 적용되며, 다음 세션부터 반영됩니다. 이상하면 끄세요.") {
                        Toggle("", isOn: $settings.localAgreement).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                }

                // 세션 음원 녹음 — 자동 삭제·보관 기간은 두지 않는다.
                // 분석하려던 증거를 앱이 먼저 지워버리는 일을 막고, 대신 사용량을 항상 보여준다.
                group("녹음") {
                    row("세션 음원 저장",
                        "대화 소리를 세션마다 파일로 남깁니다. 자막이 틀렸을 때 원인을 찾는 데 씁니다. 파일은 이 Mac 안에만 저장됩니다.") {
                        Toggle("", isOn: $settings.recordAudio).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                    divider
                    row("저장된 녹음", "세션을 삭제하면 그 세션의 녹음도 함께 지워집니다.") {
                        HStack(spacing: 10) {
                            Text(SessionRecorder.sizeLabel(recordingBytes))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink2)
                            #if os(macOS)
                            FinderRevealButton()
                            #endif
                        }
                    }
                }

                // 치환 규칙 — 표시·내보내기 시점에만, 저장 원문은 불변.
                group("치환 규칙") {
                    row("자주 틀리는 말 바로잡기",
                        "인식기가 자주 틀리는 이름·브랜드·전문용어를 화면과 내보내기에서 바로잡습니다. 위에서 아래 순서로 적용되고, 저장된 원문은 그대로 둡니다(녹취록 줄에 마우스를 올리면 원문 확인).") {
                        EmptyView()
                    }
                    ForEach(settings.replaceRules) { rule in
                        divider
                        HStack(spacing: 10) {
                            Text(rule.from).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.ink3)
                            Text(rule.to).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(rule.wholeWord ? "단어 단위" : "부분 일치")
                                .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink3)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().stroke(Theme.hair))
                            Spacer()
                            Button { settings.replaceRules.removeAll { $0.id == rule.id } } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Theme.ink3)
                                    .frame(width: 26, height: 26)
                            }.buttonStyle(.plain).help("규칙 삭제")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                    }
                    divider
                    HStack(spacing: 10) {
                        TextField("들린 대로 (예: 삼송)", text: $newFrom).textFieldStyle(.roundedBorder).frame(width: 170)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.ink3)
                        TextField("바꿀 말 (예: 삼성)", text: $newTo).textFieldStyle(.roundedBorder).frame(width: 170)
                            .onSubmit(addRule)
                        Toggle("단어 단위", isOn: $newWholeWord).toggleStyle(.switch).controlSize(.small).font(.system(size: 11.5))
                            .help("켜면 다른 단어 안의 글자는 건드리지 않습니다. 한글은 앞 경계만 검사해 조사(은/는/을)나 합성어가 붙어도 바뀝니다(정크성은 → 접근성은)")
                        Spacer()
                        Button("추가", action: addRule)
                            .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }

                Text("변경 즉시 저장됩니다 (앱을 껐다 켜도 유지).")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ink3).padding(.horizontal, 4)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { recordingBytes = SessionRecorder.totalBytes() }
    }

    private func addRule() {
        let f = newFrom.trimmingCharacters(in: .whitespaces), t = newTo.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return }
        settings.replaceRules.append(ReplaceRule(from: f, to: t, wholeWord: newWholeWord))
        newFrom = ""; newTo = ""
    }

    // ── 재사용 헬퍼 (반복 UI 단일화) ──
    private func group<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5).foregroundStyle(Theme.ink3).padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hair))
        }
    }
    private func row<C: View>(_ name: String, _ desc: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(Theme.hair).frame(height: 1) }
    private func stepBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink2).frame(width: 30, height: 26)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hair))
        }.buttonStyle(.plain)
    }
}
