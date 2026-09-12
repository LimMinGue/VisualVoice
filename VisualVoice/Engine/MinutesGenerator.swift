import Foundation
import FoundationModels

/// 회의록 상태 — 침묵 실패 금지: 미가용·실패도 화면에 사유를 표기한다.
enum MinutesState: Equatable, Codable {
    case none                  // 발화 없음/구세션
    case generating
    case ready(MeetingMinutes)
    case unavailable(String)   // 사유 문구 그대로 표시
}

struct MeetingMinutes: Equatable, Codable {
    struct Item: Equatable, Codable {
        var text: String
        var who: String = ""
        var sourceTimecodes: [String] = []   // 비어 있으면 UI가 '확인 필요' 표시
    }
    struct Participant: Equatable, Codable {
        var speakerLabel: String   // 화자 칩 라벨 ("나"/"상대 1")
        var name: String
        var detail: String
    }
    var summary: String
    var decisions: [Item]
    var actionItems: [Item]
    var participants: [Participant]
}

extension MeetingMinutes.Participant {
    /// AI가 이름을 실제로 맞혔는가. 센티넬 "이름 미상"은 완전일치가 아니라 정규화+부분일치로 방어 —
    /// 온디바이스 LLM이 "미상"·"이름 미상."·" 이름 미상" 등 변형을 낼 수 있어(검증 확증). 표시·편집·내보내기 공용.
    var hasKnownName: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !n.contains("미상")
    }
    /// 표시·내보내기 공용 값 — 이름을 못 맞힌 자리는 추정값(역할·소속=detail)을 시드, 둘 다 없으면 화자 라벨.
    /// (2026-07-18 UI 확정: 추정 배지 없이 정정만 제공)
    var displayName: String { hasKnownName ? name : (detail.isEmpty ? speakerLabel : detail) }
    /// 역할·소속 접미사 표기 여부 — 이름을 맞혔고 detail이 있고 이름과 다를 때만.
    /// name==detail(사용자가 역할을 이름으로 확정한 경우)이면 "역할 · 역할" 중복을 막는다(검증 확증).
    var showsDetailSuffix: Bool { hasKnownName && !detail.isEmpty && name != detail }
}

@Generable
private struct GenItem {
    @Guide(description: "항목 내용 한 문장")
    var text: String
    @Guide(description: "담당자 화자 라벨 — 할 일에만, 없으면 빈 문자열")
    var who: String
    @Guide(description: "근거 발화 줄 번호 목록 (녹취록의 L 번호 숫자, 예: [3, 7])")
    var sourceLines: [Int]
}

@Generable
private struct GenParticipant {
    @Guide(description: "화자 라벨 그대로 (예: 나, 상대 1)")
    var speakerLabel: String
    @Guide(description: "대화에서 추측한 이름 — 모르면 '이름 미상'")
    var name: String
    @Guide(description: "역할·소속 등 추측 근거 한 구절")
    var detail: String
}

@Generable
private struct GenNotes {
    @Guide(description: "회의 핵심 요약 2~3문장")
    var summary: String
    @Guide(description: "결정 사항 목록 — 근거 줄 번호 필수, 근거 없는 항목은 만들지 말 것")
    var decisions: [GenItem]
    @Guide(description: "할 일 목록 — 담당자 라벨·근거 줄 번호 포함")
    var actionItems: [GenItem]
    @Guide(description: "신원(이름·소속·역할)을 대화에서 추측할 수 있는 참여자만")
    var participants: [GenParticipant]
}

/// 회의록 자동 생성 — 온디바이스 FoundationModels.
/// 실측(2026-07-17): 요약 합격권 · 인니어 미지원 · 문장 교정 불합격.
enum MinutesGenerator {
    static func generate(from lines: [CaptionLine]) async -> MinutesState {
        // 가용성 사유 3종 분기(2026-09-11 SDK 인터페이스 실측) — 사용자가 고칠 수 있는 문제는 고치는 법까지.
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence가 꺼져 있어 회의록을 만들지 못했습니다 — 시스템 설정 > Apple Intelligence에서 켠 뒤 '회의록 다시 만들기'를 누르면 됩니다. 녹취록은 그대로 보존됩니다.")
        case .unavailable(.modelNotReady):
            return .unavailable("온디바이스 AI 모델을 아직 준비 중이라 회의록을 만들지 못했습니다 — 잠시 후 '회의록 다시 만들기'를 눌러 주세요. 녹취록은 그대로 보존됩니다.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("이 Mac은 온디바이스 AI를 지원하지 않아 회의록을 만들지 못했습니다. 녹취록은 그대로 보존됩니다.")
        case .unavailable:
            return .unavailable("이 Mac에서 온디바이스 AI를 쓸 수 없어 회의록을 만들지 못했습니다. 녹취록은 그대로 보존됩니다.")
        @unknown default:
            return .unavailable("이 Mac에서 온디바이스 AI를 쓸 수 없어 회의록을 만들지 못했습니다. 녹취록은 그대로 보존됩니다.")
        }
        // L번호 부여 — 결정·할 일의 근거 줄 번호를 타임코드 칩으로 역매핑하는 열쇠
        let numbered: [String] = lines.enumerated().map { i, line in
            "L\(i + 1) [\(line.speaker.label)] \(koText(of: line))"
        }
        // 청크 분할 — 온디바이스 모델 컨텍스트 한계 (2500자 단위, 결정·할 일 누적)
        var chunks: [[Int]] = [[]]
        var size = 0
        for (i, s) in numbered.enumerated() {
            if size + s.count > 2500, !chunks[chunks.count - 1].isEmpty { chunks.append([]); size = 0 }
            chunks[chunks.count - 1].append(i)
            size += s.count
        }
        var summaries: [String] = []
        var decisions: [MeetingMinutes.Item] = []
        var actions: [MeetingMinutes.Item] = []
        var participants: [MeetingMinutes.Participant] = []
        for chunk in chunks where !chunk.isEmpty {
            let text = chunk.map { numbered[$0] }.joined(separator: "\n")
            do {
                let g = try await respond(text)
                summaries.append(g.summary)
                decisions += g.decisions.map { item($0, lines: lines) }
                actions += g.actionItems.map { item($0, lines: lines) }
                for p in g.participants where !participants.contains(where: { $0.speakerLabel == p.speakerLabel }) {
                    participants.append(.init(speakerLabel: p.speakerLabel, name: p.name, detail: p.detail))
                }
            } catch {
                // 개별 청크 실패(가드레일 거부 등)가 전체를 막지 않게 — 해당 구간만 표기
                NSLog("VV minutes: 청크 생성 실패 — %@", error.localizedDescription)
                summaries.append("(이 구간 정리 실패 — 녹취록 참조)")
            }
        }
        guard summaries.contains(where: { !$0.hasPrefix("(") }) else {
            return .unavailable("회의록 생성에 실패했습니다. 녹취록은 그대로 보존됩니다.")
        }
        var summary = summaries.joined(separator: " ")
        if summaries.count > 1, let merged = try? await respondSummary(summary) {
            summary = merged   // 다청크 — 구간 요약 재요약
        }
        return .ready(.init(summary: summary, decisions: decisions,
                            actionItems: actions, participants: participants))
    }

    private static func respond(_ transcript: String) async throws -> GenNotes {
        let instructions = """
        너는 회의 녹취록을 회의록으로 정리하는 서기다. 녹취록에 실제로 있는 내용만 사용하고 추측하거나 지어내지 말라.
        결정 사항과 할 일에는 근거 발화의 줄 번호(L 번호의 숫자)를 반드시 넣어라. 근거를 못 찾으면 그 항목을 만들지 말라.
        같은 내용을 결정과 할 일에 중복해서 넣지 말라 — 할 일은 특정인이 수행할 구체적 행동만 (2026-07-17 실측: 중복 배치 관찰).
        참여자는 이름·소속·역할을 대화에서 추측할 수 있을 때만 넣어라.
        """
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: "다음 녹취록을 회의록으로 정리하라.\n\(transcript)",
                                         generating: GenNotes.self,
                                         options: GenerationOptions(temperature: 0)).content
    }

    private static func respondSummary(_ joined: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: "여러 구간의 요약을 하나의 회의 요약 2~3문장으로 합쳐라. 내용 추가 금지.")
        return try await session.respond(to: joined, options: GenerationOptions(temperature: 0)).content
    }

    private static func item(_ g: GenItem, lines: [CaptionLine]) -> MeetingMinutes.Item {
        let tcs = g.sourceLines.compactMap { n in
            lines.indices.contains(n - 1) ? lines[n - 1].timecode : nil
        }
        return .init(text: g.text, who: g.who, sourceTimecodes: tcs)   // 빈 근거 → UI '확인 필요'
    }

    /// 인니어 라인은 FM 미지원(2026-07-17 실측) — 한국어 번역이 있으면 번역을 입력으로 (타임코드 매핑 유지)
    private static func koText(of line: CaptionLine) -> String {
        func hangul(_ s: String) -> Int {
            s.unicodeScalars.lazy.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        }
        if hangul(line.source) == 0, hangul(line.translation) > 0 { return line.translation }
        return line.source
    }
}
