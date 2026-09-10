import Foundation
import FluidAudio

/// 종료 후 배치 화자 재계산 (2026-09-11 · decisions §15.5-B③).
///
/// 실시간 LS-EEND 라벨은 근사였고(§3 이원화 전반부), 후반부 '정밀 재처리'는 §14 녹음이 생기기 전엔 재료가 없었다.
/// 입력 = 세션 원음 WAV(온라인 미팅이면 시스템=상대 소리 우선, 대면이면 마이크) ·
/// 처리 = FluidAudio 오프라인 파이프라인(pyannote 세그멘테이션 + WeSpeaker 임베딩 + VBx 클러스터링 — 핀 300165b에 내장, 모델은 최초 1회 다운로드) ·
/// 출력 = 줄별 화자 재배정. **사용자 지정 줄·타이핑 줄·시계 없는 줄(마이크 스트림=나)은 건드리지 않는다.**
/// 실시간 경로(`MicTranscriptionEngine`)는 한 줄도 수정하지 않는다 — 신규 파일 + 명시적 버튼 실행만(§8·§13 불변식, §3 조용한 고쳐쓰기 금지).
/// SpectaLing 대조: 그들은 라이브 라벨을 포기하고 이 배치 경로 하나로 간다(§15.2). 우리는 둘 다 — 라이브는 '지금 누가', 배치는 '기록의 정확'.
enum OfflineDiarizer {
    struct Outcome {
        var assigned = 0          // 재배정된 줄
        var keptUserSet = 0       // 사용자가 직접 지정해 건너뛴 줄
        var noClock = 0           // 시계가 없는 줄(마이크 스트림 '나'·타이핑) — 재배정 대상 아님
        var speakersFound = 0     // 감지된 화자 수
        var requested: Int?       // 요청 인원(nil=자동)
        var sourceFile = ""
        var summary: String {
            "화자 다시 인식(\(sourceFile)): \(speakersFound)명 감지" + (requested.map { " · 요청 \($0)명" } ?? "")
            + " · \(assigned)줄 배정 · 직접 지정 \(keptUserSet)줄 유지"
        }
    }

    enum Failure: LocalizedError {
        case noRecording, models(String), processing(String)
        var errorDescription: String? {
            switch self {
            case .noRecording: return "이 세션에는 원음 녹음이 없어 화자를 다시 인식할 수 없습니다."
            case .models(let e): return "화자 인식 모델을 준비하지 못했습니다(최초 1회 다운로드 필요) — \(e)"
            case .processing(let e): return "화자 인식 처리 실패 — \(e)"
            }
        }
    }

    /// 원음 1부(-raw.wav · 롤오버 -raw-2 등은 포맷이 달라 제외). 시스템 스트림(상대 소리) 우선.
    static func sourceRecording(for sessionID: UUID) -> SessionRecorder.Item? {
        let raws = SessionRecorder.items(for: sessionID).filter {
            $0.kind == .raw && !$0.url.deletingPathExtension().lastPathComponent.contains("-raw-")
        }
        return raws.first { $0.stream == .system } ?? raws.first { $0.stream == .mic }
    }

    static func run(session: Session, numSpeakers: Int?,
                    progress: @MainActor @escaping (Int, Int) -> Void) async throws -> (lines: [CaptionLine], outcome: Outcome) {
        guard let item = sourceRecording(for: session.id) else { throw Failure.noRecording }
        var config = OfflineDiarizerConfig()
        config.clustering.numSpeakers = numSpeakers   // nil=자동 추정
        let manager = OfflineDiarizerManager(config: config)
        do { try await manager.prepareModels() } catch { throw Failure.models("\(error)") }
        let result: DiarizationResult
        do {
            result = try await manager.process(item.url) { done, total in
                Task { @MainActor in progress(done, total) }
            }
        } catch { throw Failure.processing("\(error)") }

        // 정렬 — 세그먼트는 파일 0초 기준, 줄의 clockStart/clockEnd는 세션 오디오 시계. 둘 다 첫 버퍼가 원점이라 같은 축.
        var lines = session.transcript ?? []
        var outcome = Outcome(requested: numSpeakers, sourceFile: item.url.lastPathComponent)
        var order: [String: Int] = [:]   // speakerId → 상대 N (첫 등장 순)
        for seg in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) where order[seg.speakerId] == nil {
            order[seg.speakerId] = order.count + 1
        }
        outcome.speakersFound = order.count
        for i in lines.indices {
            if lines[i].isTyped { outcome.noClock += 1; continue }
            if lines[i].speakerIsUserSet { outcome.keptUserSet += 1; continue }
            guard let s = lines[i].clockStart, let e = lines[i].clockEnd, e > s else { outcome.noClock += 1; continue }
            var overlap: [String: Double] = [:]
            for seg in result.segments where Double(seg.endTimeSeconds) > s && Double(seg.startTimeSeconds) < e {
                overlap[seg.speakerId, default: 0] += min(Double(seg.endTimeSeconds), e) - max(Double(seg.startTimeSeconds), s)
            }
            guard let best = overlap.max(by: { $0.value < $1.value })?.key, let n = order[best] else { continue }
            lines[i].speaker = .remote(n)
            lines[i].speakerUncertain = false
            lines[i].fluidSpeaker = 1000 + n   // 배치 트랙 번호(라이브 트랙과 구분) — '같은 화자 전부' 재지정의 키
            outcome.assigned += 1
        }
        return (lines, outcome)
    }
}
