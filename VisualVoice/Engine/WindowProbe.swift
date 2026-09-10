#if DEBUG
import Foundation
import AVFoundation

/// 실시간 경로 헤드리스 하네스 (2026-09-11 · decisions §15.5-C②③).
///
/// 앱을 `VV_PROBE_FILE=<오디오 경로>` 환경변수로 띄우면 창 없이 `MicTranscriptionEngine`에 파일을 **마이크 탭처럼 실시간 속도로 주입**해
/// 확정 자막을 stdout으로 찍고 종료한다. 게이트·창·확정 판정 코드를 그대로 지나므로(재현이 아니라 실물),
/// 커밋 정책·분절 규칙을 바꿀 때 무갭 자산(05·06)과 실대화 자산(04)의 회귀를 같은 코드로 잰다.
/// 라이브 경로는 한 줄도 수정하지 않는다 — 주입 소스(`Source.injected`)와 `feed()` 진입점만 추가.
///
/// 실행: VV_PROBE_FILE=.ai-docs/testkit/05_무갭_화자전환.m4a VV_PROBE_LANGS=ko,id build/dd/.../VisualVoice
enum WindowProbe {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        // 배치 화자 재계산 헤드리스 검증 — VV_PROBE_DIARIZE=<세션 UUID 접두> [VV_PROBE_SPEAKERS=N]. 저장하지 않고 결과만 찍는다.
        if let prefix = env["VV_PROBE_DIARIZE"] {
            let n = env["VV_PROBE_SPEAKERS"].flatMap(Int.init)
            Task.detached {
                do {
                    guard let session = SessionStore.load()?.first(where: { $0.id.uuidString.hasPrefix(prefix.uppercased()) }) else {
                        print("PROBE 세션 없음: \(prefix)"); exit(1)
                    }
                    let (lines, o) = try await OfflineDiarizer.run(session: session, numSpeakers: n) { d, t in print("PROBE 진행 \(d)/\(t)") }
                    print("PROBE \(o.summary)")
                    var counts: [String: Int] = [:]
                    for l in lines { counts[l.speaker.label, default: 0] += 1 }
                    print("PROBE 화자별 줄 수: \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " · "))")
                    for l in lines.prefix(12) { print("LINE [\(l.timecode)] \(l.speaker.label)\(l.speakerIsUserSet ? "(지정)" : "") \(l.source.prefix(40))") }
                } catch { print("PROBE 실패: \(error.localizedDescription)") }
                exit(0)
            }
            return
        }
        guard let path = env["VV_PROBE_FILE"] else { return }
        let langs = (env["VV_PROBE_LANGS"] ?? "ko,id").split(separator: ",").map(String.init)
        Task.detached {
            do { try await run(path: path, languages: langs) } catch { print("PROBE 실패: \(error)") }
            exit(0)
        }
    }

    private static func run(path: String, languages: [String]) async throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        // 마이크 탭 포맷 흉내 — 48kHz mono Float32 4096프레임 버퍼(엔진 변환기가 16kHz로 내린다)
        let micFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let whole = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: whole)
        let conv = AVAudioConverter(from: file.processingFormat, to: micFmt)!
        let out = AVAudioPCMBuffer(pcmFormat: micFmt,
                                   frameCapacity: AVAudioFrameCount(Double(whole.frameLength) * 48_000 / file.processingFormat.sampleRate) + 4096)!
        var fed = false
        conv.convert(to: out, error: nil) { _, st in
            if fed { st.pointee = .noDataNow; return nil }
            fed = true; st.pointee = .haveData; return whole
        }
        let total = Int(out.frameLength)
        let src = out.floatChannelData![0]

        let engine = MicTranscriptionEngine()
        var finals: [(t: Double, text: String, cont: Bool)] = []
        var volatiles = 0
        let lock = NSLock()
        let t0 = Date()
        engine.onFinal = { text, cont in
            lock.withLock { if !text.isEmpty { finals.append((Date().timeIntervalSince(t0), text, cont)) } }
        }
        engine.onVolatile = { _ in lock.withLock { volatiles += 1 } }
        engine.onStatus = { print("STATUS \($0)") }
        try await engine.start(source: .injected, localeIdentifier: "ko-KR", recognizer: .whisper,
                               whisperLanguages: languages, diarization: false)

        // 실시간 속도 주입(4096프레임 ≈ 85ms) + 끝에 무음 3초(확정 유도)
        let chunk = 4096
        var pos = 0
        let start = Date()
        let silence = AVAudioPCMBuffer(pcmFormat: micFmt, frameCapacity: AVAudioFrameCount(chunk))!
        silence.frameLength = AVAudioFrameCount(chunk)
        let silentChunks = Int(3.0 * 48_000) / chunk
        for i in 0..<((total + chunk - 1) / chunk + silentChunks) {
            let buf: AVAudioPCMBuffer
            if pos < total {
                let n = min(chunk, total - pos)
                let b = AVAudioPCMBuffer(pcmFormat: micFmt, frameCapacity: AVAudioFrameCount(chunk))!
                b.frameLength = AVAudioFrameCount(n)
                memcpy(b.floatChannelData![0], src + pos, n * MemoryLayout<Float>.size)
                pos += n
                buf = b
            } else { buf = silence }
            engine.feed(buf)
            // 실시간 페이싱 — 벽시계 기준으로 i번째 청크 시각까지 대기
            let due = start.addingTimeInterval(Double((i + 1) * chunk) / 48_000)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        }
        try await Task.sleep(for: .seconds(2))   // 마지막 틱 여유
        await engine.stop()

        let lines = lock.withLock { finals }
        print("PROBE 파일=\((path as NSString).lastPathComponent) 길이=\(String(format: "%.1f", Double(total) / 48_000))초 언어=\(languages.joined(separator: ","))")
        print("PROBE 확정 \(lines.count)줄 · 잠정 갱신 \(lock.withLock { volatiles })회")
        for l in lines {
            print(String(format: "FINAL +%5.1fs %@ %@", l.t, l.cont ? "[이어짐]" : "        ", l.text))
        }
        // 정량: 인접 단어 반복(경계 중복) 검출
        let words = lines.flatMap { $0.text.split(separator: " ").map(String.init) }
        var dup = 0
        for i in 1..<max(1, words.count) where words[i].lowercased() == words[i-1].lowercased() && words[i].count > 2 { dup += 1 }
        print("PROBE 인접 단어 중복 \(dup)건 · 총 \(words.count)단어 · 총 \(lines.reduce(0) { $0 + $1.text.count })자")
    }
}
#endif
