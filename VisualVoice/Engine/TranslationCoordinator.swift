import SwiftUI
import Translation
import NaturalLanguage

/// 확정 자막 → 상대 언어 번역 배선 (decisions §2: 자체 STT→번역 파이프라인, 문장 단위).
/// Translation framework는 SwiftUI translationTask가 공식 경로 — 큐 + invalidate 트리거 패턴.
/// 쌍(A⇄B)의 두 방향을 별도 세션(config)으로 운용, 발화별 언어는 NLLanguageRecognizer로 자동 감지.
@MainActor
final class TranslationCoordinator: ObservableObject {
    struct Job { let lineID: UUID; let text: String }

    @Published var configAtoB: TranslationSession.Configuration?
    @Published var configBtoA: TranslationSession.Configuration?
    private var queueAtoB: [Job] = []
    private var queueBtoA: [Job] = []
    private var pair = LanguagePair.koOnly

    // 실패·적체 대응(2026-09-11 · SpectaLing 대조 §15.3 ④ — 구 코드는 실패가 NSLog 한 줄, 큐는 상한 없음).
    // 배너는 연속 3회부터(청각 당사자 위원: 매 실패 노출은 자막 읽기 방해), 회복되면 자동 소멸.
    // 버려진 줄은 회복돼도 되살아나지 않으므로 별도 계수(Tester 조건 — 조용한 사라짐 금지).
    @Published private(set) var runtimeFailure: String?   // 라이브 배너 문구(nil=정상)
    @Published private(set) var failedCount = 0             // 세션 누적 실패 줄 수 — Session.notes용
    @Published private(set) var droppedCount = 0            // 큐 상한 초과로 버린 줄 수
    private var consecutiveFailures = 0
    private static let queueCap = 200                       // (번역큐상한) 소프트 변수

    /// 번역 결과 반영 콜백 (lineID, 번역문) — AppModel이 liveLines에 기록
    var apply: ((UUID, String) -> Void)?

    func configure(pair: LanguagePair) {
        self.pair = pair
        queueAtoB.removeAll(); queueBtoA.removeAll()
        runtimeFailure = nil; failedCount = 0; droppedCount = 0; consecutiveFailures = 0   // 세션 간 누수 방지
        guard !pair.isSingle else { configAtoB = nil; configBtoA = nil; return }
        let aLang = Locale.Language(identifier: pair.a.code)
        let bLang = Locale.Language(identifier: pair.b.code)
        // .highFidelity = Apple Intelligence 기반 '더 유창한' 번역(vs .lowLatency 전통 MT).
        // 워게임 2026-07-19: 실시간 문맥 창은 Apple Translation에 문맥 API가 없어 불가 → 실시간에서 가능한
        // 유일한 품질 레버가 이 전략 전환(§11.1 개정). init(preferredStrategy:)는 26.4+ → 미만/미지원 언어쌍은 기본 폴백.
        // ponytail: 지연이 문제로 실측되면 이 분기를 제거해 기본 전략으로 되돌린다.
        if #available(macOS 26.4, iOS 26.4, *) {
            configAtoB = .init(source: aLang, target: bLang, preferredStrategy: .highFidelity)
            configBtoA = .init(source: bLang, target: aLang, preferredStrategy: .highFidelity)
        } else {
            configAtoB = .init(source: aLang, target: bLang)
            configBtoA = .init(source: bLang, target: aLang)
        }
    }

    /// 확정 자막 한 줄 번역 요청 — 언어 감지 후 해당 방향 큐에 적재.
    func enqueue(lineID: UUID, text: String) {
        guard !pair.isSingle, !text.isEmpty else { return }
        if Self.detectLanguage(of: text, between: pair) == pair.a.code {
            push(Job(lineID: lineID, text: text), into: &queueAtoB)
            configAtoB?.invalidate()   // translationTask 재실행 트리거
        } else {
            push(Job(lineID: lineID, text: text), into: &queueBtoA)
            configBtoA?.invalidate()
        }
    }

    /// 큐 상한 — 초과분은 오래된 줄부터 버리고 버린 사실을 배너에 남긴다(자막은 계속 흐른다).
    private func push(_ job: Job, into queue: inout [Job]) {
        queue.append(job)
        if queue.count > Self.queueCap {
            queue.removeFirst()
            droppedCount += 1
            updateBanner()
        }
    }

    private func updateBanner() {
        var parts: [String] = []
        if consecutiveFailures >= 3 { parts.append("번역이 계속 실패하고 있어요 (연속 \(consecutiveFailures)회)") }
        if droppedCount > 0 { parts.append("밀린 번역 \(droppedCount)줄을 건너뛰었어요") }
        runtimeFailure = parts.isEmpty ? nil : parts.joined(separator: " · ") + " — 자막과 녹취는 계속 기록됩니다"
    }

    func drainAtoB(_ session: TranslationSession) async {
        let jobs = queueAtoB; queueAtoB.removeAll()
        await run(jobs, session)
    }

    func drainBtoA(_ session: TranslationSession) async {
        let jobs = queueBtoA; queueBtoA.removeAll()
        await run(jobs, session)
    }

    private func run(_ jobs: [Job], _ session: TranslationSession) async {
        for job in jobs {
            do {
                let response = try await session.translate(job.text)
                apply?(job.lineID, response.targetText)
                if consecutiveFailures > 0 { consecutiveFailures = 0; updateBanner() }   // 회복 — 배너 자동 소멸(버림 계수는 유지)
            } catch {
                failedCount += 1
                consecutiveFailures += 1
                // 오류 유형 계측 — Apple TranslationError 케이스별 문구 분기는 실측 후(규칙 1: 케이스 명세 미확인)
                NSLog("VV translate: 실패 %d(연속 %d) — %@ [%@]", failedCount, consecutiveFailures,
                      error.localizedDescription, String(describing: type(of: error)))
                if consecutiveFailures >= 3 { updateBanner() }
            }
        }
    }

    /// 쌍의 두 언어 중 어느 쪽인지 감지 (제약을 걸어 오감지 최소화)
    /// nonisolated — 순수 함수(NLLanguageRecognizer 지역 생성). AI 재번역(비메인 액터)도 재사용.
    nonisolated static func detectLanguage(of text: String, between pair: LanguagePair) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [NLLanguage(rawValue: pair.a.code),
                                          NLLanguage(rawValue: pair.b.code)]
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? pair.a.code
    }
}
