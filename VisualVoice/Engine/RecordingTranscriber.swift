import Foundation
import WhisperKit

/// 녹음 재전사 (2026-09-11 · decisions §15.5-B④) — §14.1이 정의한 분석 루프
/// "녹음 → 더 큰 STT로 정답 대본 → 앱 자막과 대조"를 앱 안에서 닫는다.
///
/// 게이트·0.45초 틱·잠정 없이 **파일 통짜 전사**(WhisperKit 장문 VAD 청킹) — 라이브가 놓친 발화가 무엇인지 그대로 드러난다.
/// 모델 = 라이브와 같은 공유 파이프(turbo 632MB · 추가 다운로드 0). ponytail: large-v3 정식판 별도 로드는 실측에서 turbo가 부족할 때.
/// 환각 방어는 라이브와 같은 세그먼트 신뢰도 3종 + 상용구 사전을 그대로 — 정답 대본이 환각을 '정답'으로 삼으면 대조가 무의미.
/// 세션 진행 중 실행 금지(공유 파이프 경쟁 → 라이브 자막 지연) — 호출부(AppModel)가 막는다.
enum RecordingTranscriber {
    enum Failure: LocalizedError {
        case noRecording, load(String), transcribe(String)
        var errorDescription: String? {
            switch self {
            case .noRecording: return "이 세션에는 원음 녹음이 없어 다시 전사할 수 없습니다."
            case .load(let e): return "녹음 파일을 읽지 못했습니다 — \(e)"
            case .transcribe(let e): return "재전사 실패 — \(e)"
            }
        }
    }

    struct Outcome {
        var lines: [CaptionLine] = []
        var files: [String] = []
        var info: String { "재전사 · WhisperKit \(MicTranscriptionEngine.whisperModelName) · \(files.joined(separator: ", ")) · \(lines.count)줄" }
    }

    /// 원음 1부 전부(온라인 미팅=시스템+마이크 2파일, 대면=마이크 1파일)를 전사해 시각순으로 합친다.
    /// 마이크 스트림 줄은 온라인 미팅에서만 '나'(§12 규약과 동일), 대면 대화의 마이크는 화자 미상.
    static func run(session: Session, pair: LanguagePair, dual: Bool,
                    onStatus: @MainActor @escaping (String) -> Void) async throws -> Outcome {
        let raws = SessionRecorder.items(for: session.id).filter {
            $0.kind == .raw && !$0.url.deletingPathExtension().lastPathComponent.contains("-raw-")   // 롤오버 부(-raw-2) 제외
        }
        guard !raws.isEmpty else { throw Failure.noRecording }
        await onStatus("Whisper 모델 준비 중…")
        let pipe = try await MicTranscriptionEngine.sharedWhisperPipe()

        var outcome = Outcome()
        for item in raws {
            await onStatus("재전사 중 — \(item.url.lastPathComponent)")
            let samples: [Float]
            do { samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: item.url.path) }
            catch { throw Failure.load("\(error)") }
            var options = DecodingOptions()
            options.task = .transcribe
            if pair.isSingle { options.language = pair.a.code } else { options.detectLanguage = true }
            options.chunkingStrategy = .vad   // 장문 — 무음 경계로 30초 창 분할(WhisperKit 내장)
            var results: [TranscriptionResult]
            do { results = try await pipe.transcribe(audioArray: samples, decodeOptions: options) }
            catch { throw Failure.transcribe("\(error)") }
            // 쌍 클램프(라이브 `whisperTick`과 같은 규약 — decisions §2): 자동 감지가 쌍 밖(영어·중국어 등)으로 샌 청크는
            // 직전 유효 언어(대화 관성) 또는 언어 1로 그 구간만 재전사. 2026-09-11 실측: 클램프 없이 통짜 전사하면
            // 한·인니가 한 줄에 섞이고 파편("-"·"B.J.L.")이 늘어 '정답 대본'이 라이브보다 나빠졌다(8/9 세션 726자 vs 1253자).
            if !pair.isSingle {
                let allowed = Set([pair.a.code, pair.b.code])
                var sticky = pair.a.code
                for i in results.indices {
                    let lang = results[i].language
                    if allowed.contains(lang) { sticky = lang; continue }
                    let segs = results[i].segments
                    guard let s0 = segs.map(\.start).min(), let e0 = segs.map(\.end).max(), e0 > s0 else { continue }
                    let lo = max(0, Int(s0 * 16000)), hi = min(samples.count, Int(e0 * 16000))
                    guard hi > lo + 16000 else { continue }
                    var retry = options
                    retry.detectLanguage = false
                    retry.language = sticky
                    retry.chunkingStrategy = nil
                    if let clamped = try? await pipe.transcribe(audioArray: Array(samples[lo..<hi]), decodeOptions: retry).first {
                        // 재전사 세그먼트 시각은 슬라이스 기준 0초 → 원 파일 시각으로 되돌린다(필드가 전부 var라 제자리 수정)
                        results[i].segments = clamped.segments.map { seg in
                            var s = seg; s.start += s0; s.end += s0; return s
                        }
                        results[i].text = clamped.text
                        results[i].language = sticky
                    }
                }
            }
            let speaker: Speaker = (item.stream == .mic && dual) ? .me : .unlabeled
            for r in results {
                for seg in r.segments {
                    let trusted = seg.noSpeechProb < 0.5 && seg.avgLogprob > -1.1 && seg.compressionRatio < 2.4
                    guard trusted else { continue }
                    let cleaned = MicTranscriptionEngine.cleanHallucinations(seg.text)
                    if cleaned.isEmpty || MicTranscriptionEngine.isStockHallucination(cleaned) { continue }
                    outcome.lines.append(CaptionLine(speaker: speaker, source: cleaned, translation: "",
                                                     timecode: LiveMetrics.format(Double(seg.start)),
                                                     clockStart: Double(seg.start), clockEnd: Double(seg.end)))
                }
            }
            outcome.files.append(item.url.lastPathComponent)
        }
        outcome.lines.sort { ($0.clockStart ?? 0) < ($1.clockStart ?? 0) }
        return outcome
    }
}
