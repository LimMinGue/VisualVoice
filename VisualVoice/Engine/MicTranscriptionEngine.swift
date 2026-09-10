import AVFoundation
import Speech
import SoundAnalysis
import WhisperKit
import FluidAudio

/// 마이크/시스템 오디오 → SpeechTranscriber(macOS 26 온디바이스) 실시간 전사 엔진.
/// 무음 등으로 인식 스트림이 죽으면 자동 재시작해 세션을 이어간다(2026-07-17 실측 버그 수정).
/// 단순화: 아직 TranscriptionSource 프로토콜 추상 없음 — WhisperKit(인니) 붙일 때 추출.
final class MicTranscriptionEngine {

    // 콜백 (오디오/백그라운드 스레드에서 호출될 수 있음 — 수신측에서 MainActor 홉)
    var onVolatile: ((String) -> Void)?      // 잠정(받아쓰는 중) 텍스트 — 세그먼트 누적치
    var onFinal: ((String, Bool) -> Void)?   // (확정 텍스트, 이어짐 힌트 — 6초 상한 절단=true·무음 종결=false)
    var onLevel: ((Float) -> Void)?          // 입력 레벨 0~1 (무음 감지·미터용)
    var onStatus: ((String) -> Void)?        // 준비 단계 안내(모델 다운로드 등)
    var onRecognitionRestart: (() -> Void)?  // 인식 세션 자동 재시작 직전(잠정 자막 확정 처리용)

    /// 입력원 — 대면 대화=마이크 / 온라인 미팅=시스템 오디오(SCK) / injected=헤드리스 하네스 주입(DEBUG · WindowProbe)
    enum Source { case mic, systemAudio, injected }

    #if DEBUG
    /// 하네스 전용 진입 — 마이크 탭 콜백과 같은 경로로 버퍼를 넣는다(게이트·창·확정 판정 무수정).
    func feed(_ buffer: AVAudioPCMBuffer) { process(buffer) }
    #endif

    /// 인식기 — 한/영=Apple SpeechTranscriber, 인니 포함=WhisperKit (decisions §2 엔진 라우팅)
    enum Recognizer { case apple, whisper }

    private let audioEngine = AVAudioEngine()
    #if os(macOS)
    private var systemTap: SystemAudioTap?
    private var usingSystemTap: Bool { systemTap != nil }
    #else
    private let usingSystemTap = false   // iPad = 마이크 전용, 시스템 오디오 제외 (decisions §10)
    #endif
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var locale = Locale(identifier: "ko-KR")
    private var isPaused = false
    private var isStopping = false
    private var dropCount = 0          // 변환 실패 폐기 계수(침묵 실패 계측)
    private var bufferCount = 0
    private var lastBufferAt = Date()  // 오디오 스레드에서 갱신 — 워치독 판독용(미세 레이스 허용)

    // ── Whisper 경로 (인니어 — Apple 미지원 언어의 유일한 온디바이스 길, decisions §2) ──
    private var recognizerKind: Recognizer = .apple
    private var whisper: WhisperKit?
    private var whisperLanguages: [String] = ["id"]   // 1개=고정, 2개=쌍 클램프(둘 중 확률 높은 쪽만)
    private var whisperSamples: [Float] = []          // 16kHz mono 누적 창
    private var whisperLoudSeconds = 0.0              // 창 내 '사람 말'(VAD 판정) 누적 초 — 발화량 게이트 (whisperLock 보호)
    private var whisperPreRoll: [Float] = []          // 게이트 닫힘 중 최근 1초 링 — 어두 절단 방지 (오디오 스레드 전용)
    private var whisperGateWasOpen = false            // 게이트 개방 순간(전이) 감지용
    private let whisperLock = NSLock()
    // ── 음성 분류 게이트 (SoundAnalysis VAD — wargame 2026-07-17: 소음≈발화 방에서 에너지 게이트 한계 도달) ──
    private var soundAnalyzer: SNAudioStreamAnalyzer?
    private var soundObserver: SpeechClassObserver?    // SNRequest observer는 약참조 — 강참조 유지 필수
    private var speechClassifierReady = false          // false = 페일오픈(에너지 단독)
    private var lastSpeechClassAt = Date.distantPast   // 마지막 '사람 말' 분류 시각
    private var snFramePos: AVAudioFramePosition = 0
    private var whisperTask: Task<Void, Never>?
    private var whisperBusy = false
    private var whisperBusySince: Date?     // 행(hang) 계측
    private var whisperBusyWarned = false
    private var whisperLastHypothesis = ""
    private var whisperStableTicks = 0        // 같은 가설 연속 횟수 — 문장 안정 기반 확정
    /// LocalAgreement(세그먼트 단위) 실험 — 2026-09-11 §15.5-C②. 직전 틱과 **앞부분 세그먼트가 그대로 일치**하고 꼬리는
    /// 아직 변하는 중이면, 일치한 앞부분만 앞당겨 확정하고 창을 그 끝까지 비운다. 무갭 발화(05·06)가 6초 상한까지 뭉쳐
    /// 한 줄 garble + 언어 혼입되던 구조적 원인(전체 문자열 일치 2틱 규칙)에 대한 대안. **기본 OFF** — 하네스(WindowProbe)로
    /// 04 무회귀(중복 0·어두 생존)와 05 개선을 함께 확인한 뒤 제작자 실측·결정. 켜기: 환경변수 VV_LA=1.
    /// 하네스 실측(2026-09-11): 04 실대화 무회귀(4줄·중복 0·어두 전부 생존) · 05 무갭 1줄 garble → 4줄 정확 · 06 무회귀.
    /// 켜기: 설정 토글(`vv.localAgreement`) 또는 환경변수 VV_LA=1(하네스). 세션 시작 시 1회 읽는다.
    static let localAgreementKey = "vv.localAgreement"
    private static var localAgreement: Bool {
        ProcessInfo.processInfo.environment["VV_LA"] == "1" || UserDefaults.standard.bool(forKey: localAgreementKey)
    }
    private var whisperPrevSegments: [String] = []   // 직전 틱의 신뢰 세그먼트 텍스트(정규화 후) — 접두 일치 판정용
    private var whisperStickyLanguage: String?   // 직전 확정 언어(쌍 클램프의 대화 관성)
    /// 전사 게이트 — 이 구간만 Whisper 버퍼에 적재. 발화가 끝나면 유입도 멈춰 문장 확정이 즉시 이뤄짐(핑퐁 리듬).
    ///
    /// **판정 기준 = 음성 분류(VAD)** — 절대 RMS 임계는 폐기(2026-07-25 실측 확정, decisions §13).
    /// 구 임계(적재 0.14 / 발화량 0.17)는 마이크 근접 발화 기준이라 거리별 생존율이 벼랑이었다:
    ///   0.5m(나) 94% → **1.0m 0% → 1.5m(앞사람) 0% → 2.0m 0%** (대면 대화에서 상대 답변 전량 폐기).
    /// 임계 조정으로 못 고친다 — 1.5m 발화의 광대역 RMS 0.114 ≈ 방 소음 바닥 0.10이라 에너지 축에서 겹친다
    /// (적응형 게이트안도 같은 실측에서 생존율 0%). 같은 오디오에서 SoundAnalysis 분류는 1.5m 95~98% 검출.
    /// 환각 방어는 그대로 4층 유지 — 신뢰도 필터 3종·환각 사전·프리롤이 담당(순수 소음 60초 VAD 오검출 0% 실측).
    private let whisperGate: Float = 0.14          // 분류기 불가 시 페일오픈 폴백 + 근접 전용 스트림
    private let silenceFloor: Float = 0.02         // 디지털 무음 하한 — 음소거 마이크가 게이트를 여는 것만 차단
    private var gateOpenUntil = Date.distantPast
    /// 근접 발화만 받는 스트림(온라인 미팅의 '내 마이크') — 확정이 무조건 '나'라서 감도 확대가 곧 화자 오배정.
    /// ⚠️ 한계: Whisper 경로에만 적용된다. Apple 경로(한 단일·한↔영)는 게이트 자체가 없어(process의 .apple 분기)
    /// 이 스트림도 무게이트다 — 그 조합의 화자 오배정은 후속 과제.
    private var nearFieldOnly = false
    /// 창 무효화 세대 — 진행 중 전사가 옛 스냅샷 좌표로 트림·발신하는 것을 차단 (whisperLock 보호).
    private var audioGeneration = 0

    // ── 레벨 계측 (게이트 임계 실측 보정용 — 소음/발화 분포 비교, 2026-07-17) ──
    // 클리핑된 level(min(1, rms*18))이 아니라 원시 RMS를 기록 — 1.0 포화로 분포가 안 보이던 문제 수정
    // 오디오 스레드 전용 접근 — 잠금 불필요
    private var rmsWindow: [Float] = []
    private var gateOpenBuffers = 0
    private var statBuffers = 0
    private var fedSeconds = 0.0
    private var lastLevelLogAt = Date()

    // ── 화자 분리 (FluidAudio LS-EEND — 워게임 2026-07-17 확정) ──
    struct SpeakerSegment {
        let speakerIndex: Int
        let start: Double     // 오디오 시계 기준 초
        let end: Double
        let finalized: Bool
    }
    var onSpeakerSegments: (([SpeakerSegment]) -> Void)?
    private var diarizer: LSEENDDiarizer?
    private var diarSamples: [Float] = []
    private var diarClockOrigin: Double = -1   // 디아라이저 첫 공급 시 audioClock — 세그먼트 시각(누적)↔자막 시계 정렬(Route B #3, 2026-07-18 QC 실측)
    private let diarLock = NSLock()
    private var diarTask: Task<Void, Never>?
    /// 공급된 오디오 누적 초 — 자막↔화자 세그먼트 정렬용 공통 시계
    private(set) var audioClock: Double = 0
    private var lastLoudBufferAt = Date()             // 무음 분절 판단(오디오 스레드 기준)
    /// 2026-07-17 상향: small → large-v3 turbo 632MB — 원문 대조 실측에서 치환 오류(따뜻해→짰다·익숙→이식) 확인.
    /// turbo = 얇은 디코더(large급 정확도·small급에 근접한 속도). `(whisperkit_model)` 소프트 변수 소진.
    /// 단일 상수(2026-09-11) — preheatWhisper의 복사본 리터럴과 세션 메타(modelUsed)가 이 값을 공유한다.
    /// 출처: HF `argmaxinc/whisperkit-coreml` — 리비전 미핀(WhisperKit이 폴더명으로만 조회, §15.5-A⑧).
    /// SpectaLing 라이브 기본값도 정확히 같은 모델(설정 화면 실측 "Large v3 Turbo (Compact) 632MB").
    static let whisperModelName = "large-v3-v20240930_turbo_632MB"
    private var whisperModel: String { Self.whisperModelName }

    // ── Whisper 공유 (decisions §12 `(whisper_공유)` — 온라인 미팅 2엔진의 632MB 이중 로드 방지) ──
    // 인스턴스 1개를 전 엔진이 공유(메모이즈 — 세션 간 재로드도 제거) + transcribe 구간 전역 직렬화.
    // 직렬화는 대기 큐 없이 "놓치면 다음 틱(0.45초)에 재시도" — 기존 whisperBusy와 같은 스킵 문법.
    private static let sharedWhisperLock = NSLock()
    private static var sharedPipeTask: Task<WhisperKit, Error>?
    private static var sharedTranscribing = false

    private static func acquireTranscribe() -> Bool {
        sharedWhisperLock.withLock {
            if sharedTranscribing { return false }
            sharedTranscribing = true
            return true
        }
    }
    private static func releaseTranscribe() {
        sharedWhisperLock.withLock { sharedTranscribing = false }
    }

    /// 공유 파이프 로드(1회) — 실패 시 메모 해제(다음 세션 재시도 가능). 로드 로직은 기존 캐시 우선 경로 그대로.
    /// onStatus = 최초 로더의 상태 보고 채널(재다운로드 폴백 문구 정직화 유지 — 2026-07-17 문구 3종).
    private static func sharedWhisper(model: String, onStatus: ((String) -> Void)?) async throws -> WhisperKit {
        let task = sharedWhisperLock.withLock { () -> Task<WhisperKit, Error> in
            if let t = sharedPipeTask { return t }
            let t = Task { try await loadWhisperPipe(model: model, onStatus: onStatus) }
            sharedPipeTask = t
            return t
        }
        do { return try await task.value }
        catch {
            sharedWhisperLock.withLock { if sharedPipeTask == task { sharedPipeTask = nil } }
            throw error
        }
    }

    /// 재전사(RecordingTranscriber)용 공유 파이프 접근 — 로드·캐시 규약 동일, 추가 다운로드 없음(2026-09-11 B④).
    static func sharedWhisperPipe(onStatus: ((String) -> Void)? = nil) async throws -> WhisperKit {
        try await sharedWhisper(model: whisperModelName, onStatus: onStatus)
    }

    private static func loadWhisperPipe(model: String, onStatus: ((String) -> Void)?) async throws -> WhisperKit {
        // 캐시가 있으면 modelFolder 직접 지정으로 로컬 로드(네트워크 0회 — 오프라인 동작).
        // WhisperKit(model:)만 쓰면 캐시가 있어도 매번 허깅페이스 파일 목록을 조회해
        // 오프라인에서 세션 시작 자체가 실패한다(2026-07-17 패키지 소스 실측 확정).
        let cachedFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(model)")
        let hasCache = FileManager.default.fileExists(atPath: cachedFolder.path)
        if hasCache, let local = try? await WhisperKit(model: model, modelFolder: cachedFolder.path) {
            NSLog("VV whisper: 로컬 캐시 로드 (네트워크 미사용) — %@", cachedFolder.path)
            return local
        }
        // 캐시 부재 또는 손상(불완전 다운로드) → 다운로드 경로 폴백(자기 복구)
        if hasCache {
            NSLog("VV whisper: 로컬 캐시 로드 실패 — 재다운로드 폴백")
            onStatus?("Whisper 모델 다시 다운로드 중… (네트워크 필요)")
        }
        return try await WhisperKit(model: model)
    }

    /// 마지막 오디오 버퍼 이후 경과 — AppModel 워치독이 "입력이 끊겼는데 세션은 산 척"을 감지
    var secondsSinceLastBuffer: TimeInterval { Date().timeIntervalSince(lastBufferAt) }

    /// 읽어주기(TTS) 재생 중 마이크 차단 — 자기 소리 재자막 루프 방지(§1-⑧).
    /// 시스템 오디오는 SCK가 자기 프로세스 소리를 제외하므로 마이크 탭만 차단. (쓰기=메인, 읽기=오디오 스레드 — Bool 단순 경합 허용)
    var micMuted = false

    /// 세션 음원 녹음 — nil이면 녹음하지 않는다(설정 토글). 전사 판정에는 일절 관여하지 않는 읽기 분기.
    /// 소유·수명은 AppModel(세션 시작 시 주입, stop()에서 마감) — decisions §14.
    var recorder: SessionRecorder?

    private var lastKickAt = Date.distantPast

    /// 워치독 복구 — 구성 변경으로 멈춘 엔진을 탭 제거→리셋→새 포맷 재설치로 완전 재구성.
    /// (단순 start()는 구성 안정 전 -10868로 계속 실패 — 2026-07-17 로그 실측: 복구 11초 → 재구성으로 단축)
    func kickAudio() {
        guard !usingSystemTap, !isStopping, !isPaused else { return }
        guard Date().timeIntervalSince(lastKickAt) > 2 else { return }   // 0.5초 티커 난타 방지
        lastKickAt = Date()
        if audioEngine.isRunning {
            NSLog("VV watchdog: 엔진 isRunning=1 — 버퍼만 끊김(관찰 지속)")
            return
        }
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            NSLog("VV watchdog: 입력 포맷 아직 무효 — 다음 틱 재시도")
            return
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self, !self.micMuted else { return }   // 읽어주기(TTS) 재생 중 마이크 차단
            self.process(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            NSLog("VV watchdog: 엔진 재구성 성공 (%.0fHz %dch)", fmt.sampleRate, fmt.channelCount)
        } catch {
            NSLog("VV watchdog: 재구성 실패 — %@", error.localizedDescription)
        }
    }

    enum EngineError: LocalizedError {
        case micDenied, localeUnsupported(String), noAnalyzerFormat, systemAudioUnavailable
        var errorDescription: String? {
            switch self {
            case .micDenied: return "마이크 권한이 거부되었습니다. 시스템 설정 > 개인정보 보호 > 마이크에서 허용해 주세요."
            case .localeUnsupported(let l): return "이 언어(\(l))는 온디바이스 인식을 지원하지 않습니다."
            case .noAnalyzerFormat: return "오디오 형식 협상에 실패했습니다."
            case .systemAudioUnavailable: return "이 기기에서는 시스템 오디오 캡처를 지원하지 않습니다."
            }
        }
    }

    /// 앱 실행 직후 백그라운드 사전 설치+예열 — 세션 시작 전에 모델을 준비해 첫 자막 콜드 스타트 제거.
    /// (Apple STT 모델은 앱 번들 탑재 불가 — AssetInventory 시스템 자산. 마이크 권한 불필요 단계라 조용히 실행 가능)
    static func preheatAssets(localeIdentifier: String) async {
        let locale = Locale(identifier: localeIdentifier)
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47).lowercased() == locale.identifier(.bcp47).lowercased()
        }) else { return }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [])
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        try? await analyzer.prepareToAnalyze(in: format)
    }

    /// 인니 STT(WhisperKit) 모델 선다운로드 — 온보딩 언어팩 준비용. 인스턴스 생성이 다운로드 트리거(캐시 있으면 빠름).
    static func preheatWhisper() async {
        _ = try? await WhisperKit(model: whisperModelName)
    }

    func start(source: Source = .mic, localeIdentifier: String,
               recognizer: Recognizer = .apple, whisperLanguages: [String] = ["id"],
               diarization: Bool = true, nearFieldOnly: Bool = false) async throws {
        recognizerKind = recognizer
        self.whisperLanguages = whisperLanguages
        self.nearFieldOnly = nearFieldOnly

        // 1) 권한 — 마이크 소스만 마이크 권한 필요 (시스템 오디오는 화면 기록 권한, SCK 조회 시 프롬프트)
        if source == .mic {
            onStatus?("마이크 권한 확인 중…")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw EngineError.micDenied }
        }

        switch recognizer {
        case .apple:
            // 2) 로케일 지원 확인 (실측 게이트 — supportedLocales 런타임 조회)
            let requested = Locale(identifier: localeIdentifier)
            let supported = await SpeechTranscriber.supportedLocales
            guard supported.contains(where: {
                $0.identifier(.bcp47).lowercased() == requested.identifier(.bcp47).lowercased()
            }) else { throw EngineError.localeUnsupported(localeIdentifier) }
            locale = requested
            // 3) 인식 세션 시작 (무음 등으로 죽으면 자동 재시작되는 단위)
            try await startRecognition(installAssets: true)
        case .whisper:
            try await startWhisper()
        }

        // 4) 오디오 소스 연결 — 공용 process()로 합류 (변환기는 소스 포맷에 맞춰 지연 생성)
        switch source {
        case .mic:
            #if os(iOS)
            // iOS는 오디오 세션 명시 활성 필요(macOS엔 없는 개념) — 녹음+재생(읽어주기 TTS) 동시 (decisions §10)
            let avSession = AVAudioSession.sharedInstance()
            try avSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try avSession.setActive(true)
            #endif
            let input = audioEngine.inputNode
            // 음성 처리(VP)는 2026-07-17 실측 회귀로 롤백: 켜면 레벨 미터는 움직이나 자막 전무.
            // TTS 자기 소리 재자막 차단은 VP 대신 '재생 중 입력 무시' 플래그로 해결 예정(§1-⑧ 계획대로).
            let micFormat = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
                guard let self, !self.micMuted else { return }   // 읽어주기(TTS) 재생 중 마이크 차단 (§1-⑧)
                self.process(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            // 구성 변경(입력 장치 전환·샘플레이트 변경 등)으로 엔진이 스스로 멈추는 경우 자동 재기동
            // 단순화: 옵서버 블록이 @Sendable이라 non-Sendable self 캡처에 Swift 6 경고 1건 잔존 —
            // 근본 해결은 엔진 전체를 @MainActor로 격리하는 대규모 마이그레이션. 실사용 경로라 지금은 defer
            // (kickAudio는 main에서만·재진입 가드 2초로 안전). 락 6건(→Swift 6 에러)은 withLock으로 해소 완료.
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: nil
            ) { [weak self] _ in
                NSLog("VV audio: 엔진 구성 변경 감지")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.kickAudio() }
            }
            onStatus?("듣는 중 (마이크)")
        case .injected:
            onStatus?("주입 모드(하네스) — feed()로 버퍼 공급")   // 탭·엔진 없음. stop()의 removeTap은 무해(설치된 탭 없음)
        case .systemAudio:
            #if os(macOS)
            onStatus?("화면 기록 권한 확인 중… (시스템 오디오 캡처에 필요)")
            let tap = SystemAudioTap(
                onBuffer: { [weak self] buffer in self?.process(buffer) },
                onEvent: { [weak self] msg in self?.onStatus?(msg) })
            try await tap.start()
            systemTap = tap
            onStatus?("캡처 시작 — 소리가 나면 자막이 시작됩니다")
            #else
            throw EngineError.systemAudioUnavailable   // iPad UI엔 진입 경로 없음 — 방어선 (decisions §10)
            #endif
        }

        // 화자 분리 초기화 — 백그라운드, 실패해도 자막은 계속(소프트 실패). 자막이 먼저, 화자 라벨은 준비되는 대로.
        // 온라인 미팅의 마이크 엔진은 diarization=false — 마이크 확정=무조건 '나'라 분리기 불필요 (decisions §12).
        guard diarization else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let d = LSEENDDiarizer()
                try await d.initialize(variant: .ami, stepSize: .step100ms)   // AMI = 회의 코퍼스
                self.diarizer = d
                self.startDiarLoop()
                NSLog("VV diar: LS-EEND(ami) 준비 완료")
            } catch {
                NSLog("VV diar: 초기화 실패(자막은 계속) — %@", error.localizedDescription)
            }
        }
    }

    private func startDiarLoop() {
        diarTask = Task { [weak self] in
            while let self, !self.isStopping {
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.diarTick()
            }
        }
    }

    private func diarTick() {
        guard let diarizer else { return }
        diarLock.lock()
        let chunk = diarSamples
        let origin = max(0, diarClockOrigin)   // 세그먼트 시각(디아라이저 누적)에 첫 공급 절대시각 가산 → 자막 시계와 정렬
        diarSamples.removeAll()
        diarLock.unlock()
        guard !chunk.isEmpty else { return }
        let rate = analyzerFormat?.sampleRate ?? 16000
        guard let update = try? diarizer.process(samples: chunk, sourceSampleRate: rate) else { return }
        var segments: [SpeakerSegment] = []
        for seg in update.finalizedSegments {
            segments.append(SpeakerSegment(speakerIndex: seg.speakerIndex,
                                           start: Double(seg.startTime) + origin, end: Double(seg.endTime) + origin, finalized: true))
        }
        for seg in update.tentativeSegments {
            segments.append(SpeakerSegment(speakerIndex: seg.speakerIndex,
                                           start: Double(seg.startTime) + origin, end: Double(seg.endTime) + origin, finalized: false))
        }
        if !segments.isEmpty { onSpeakerSegments?(segments) }
    }

    /// WhisperKit 경로 — 16kHz 창 누적 → 주기 전사(잠정) → 무음/상한 분절 시 확정.
    /// 모델은 최초 1회 다운로드(네트워크 필요), 이후 온디바이스 캐시.
    private func startWhisper() async throws {
        let cachedFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(whisperModel)")
        let hasCache = FileManager.default.fileExists(atPath: cachedFolder.path)
        onStatus?(hasCache ? "Whisper 모델 로딩 중…" : "Whisper 모델 다운로드 중… (최초 1회, 네트워크 필요)")
        // 공유 파이프(§12 (whisper_공유)) — 2엔진 동시 세션도, 다음 세션도 로드 1회.
        let pipe = try await Self.sharedWhisper(model: whisperModel, onStatus: onStatus)
        whisper = pipe
        // 분석기 포맷 = Whisper 기대 입력(16kHz mono Float32) — 기존 변환 파이프라인 재사용
        analyzerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 16000, channels: 1, interleaved: false)
        // 음성 분류 게이트(wargame 2026-07-17) — 소음≈발화 방에서 에너지 게이트의 구조적 방어선. 실패 시 페일오픈.
        if let fmt = analyzerFormat, let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            request.windowDuration = CMTime(seconds: 0.75, preferredTimescale: 16_000)   // (분류_창) 소프트 변수
            request.overlapFactor = 0.5
            let analyzer = SNAudioStreamAnalyzer(format: fmt)
            let observer = SpeechClassObserver { [weak self] in self?.lastSpeechClassAt = Date() }
            if (try? analyzer.add(request, withObserver: observer)) != nil {
                soundAnalyzer = analyzer
                soundObserver = observer
                speechClassifierReady = true
                NSLog("VV vad: SoundAnalysis 음성 분류 게이트 활성")
            }
        }
        if !speechClassifierReady { NSLog("VV vad: 분류기 불가 — 에너지 게이트 단독(페일오픈)") }
        // 예열 — 최초 CoreML 컴파일(수십 초)을 준비 단계에서 소화 (첫 자막 24.5초 실측 → 대응)
        onStatus?("Whisper 모델 예열 중…")
        var warmupOptions = DecodingOptions()
        warmupOptions.task = .transcribe
        warmupOptions.language = whisperLanguages.first ?? "id"
        _ = try? await pipe.transcribe(audioArray: [Float](repeating: 0, count: 16000),
                                       decodeOptions: warmupOptions)

        whisperTask = Task { [weak self] in
            while let self, !self.isStopping {
                try? await Task.sleep(nanoseconds: 450_000_000)   // 0.9→0.45초 — 잠정 갱신 2배 (2026-07-17 실측 "반응이 느리다")
                await self.whisperTick()
            }
        }
        onStatus?("Whisper 준비 완료")
        NSLog("VV whisper: 모델 %@ 로드·예열 완료", whisperModel)
    }

    private func whisperTick() async {
        guard let whisper, !whisperBusy, !isPaused else {
            // 행(hang) 가시화 — 전사가 20초 이상 안 돌아오면 1회 경고 (오류형/행형 판별용 계측)
            if whisperBusy, let since = whisperBusySince, !whisperBusyWarned,
               Date().timeIntervalSince(since) > 20 {
                whisperBusyWarned = true
                NSLog("VV whisper: 경고 — 전사가 %.0f초째 미완 (행 의심)", Date().timeIntervalSince(since))
            }
            return
        }
        // 세대 토큰 동반 스냅샷 — 아래 removeCount·onFinal은 전부 이 스냅샷 좌표 기준이라,
        // await 동안 창이 밖에서 무효화되면(토글 OFF·상한 절단) 좌표가 어긋난다.
        let (samples, loudSeconds, generation) = whisperLock.withLock {
            (whisperSamples, whisperLoudSeconds, audioGeneration)
        }
        guard samples.count >= 16000 else { return }   // 1초 미만이면 대기

        // 발화량 게이트 — 창에 '사람 말'이 (발화량요구)초 미만이면 전사 생략·폐기.
        // 발화 직후 꼬리 무음 창이 통과해 "Terima kasih." 환각을 지어내던 문제 차단 (2026-07-17 실측).
        // 소음이 확정에 도달할 수 없어 문맥 리셋(구 가드④)은 불필요 — 폐기(decisions §7 개정).
        // 누적 기준은 2026-07-25에 RMS>0.17 → VAD 판정으로 교체(speechDetected) — 구 기준은 원거리 발화가
        // 0.17을 영영 못 넘어 상대 답변이 전량 폐기됐다(거리별 생존율 1.0m부터 0%, decisions §13).
        let bufferSec = Double(samples.count) / 16000.0
        // 창 단위 재확인 — 적재는 버퍼 단위 VAD로 걸렀고, 여기선 창 구간에 분류 이력이 살아있는지 본다.
        // (유효_시간) 창 길이+1.0초 · 페일오픈: 분류기 없으면 에너지 단독.
        let speechSeen = !speechClassifierReady
            || Date().timeIntervalSince(lastSpeechClassAt) < bufferSec + 1.0
        // (발화량요구) 0.7초 — 임의값 아니라 신선도(0.6초)에서 유도된 값이다. 분류 1회는 voiced를 최대
        // 0.6초만 켜므로, 요구가 그보다 커야 '단발 오검출(의자 끄는 소리 등)이 게이트를 혼자 통과'하는
        // 경로가 닫힌다 — 사실상 분류 2회(≈실제 발화 0.75초)를 요구하는 것과 같다.
        // 실측 비용(하네스 4자산): 원거리 생존율 92% → 90%, 근접 변화 없음. 구 0.3초는 단발로 통과했다.
        if loudSeconds < 0.7 || !speechSeen {
            // 발화 램프업 유보: 게이트가 열려 있는 동안은 폐기하지 않고 대기 —
            // 첫 틱(말소리 아직 0.3초 미만)에 어두를 버리던 경로 차단 (2026-07-17 원문 대조 실측).
            // ⚠️ 탈출구 필수: 게이트가 '사람 말 아닌 신호'로 계속 열려 있으면(페일오픈 상태의 팬 소음,
            // 근접 전용 스트림의 원거리 웅성거림) 이 guard가 트림을 영원히 막아 창이 고착되고 자막이 멎는다.
            // 6초는 확정 상한과 같은 값 — 그만큼 쌓이도록 발화량이 0이면 '램프업 중'이 아님이 확정적이다.
            guard Date() >= gateOpenUntil || bufferSec > 6 else { return }
            whisperLock.withLock {
                whisperSamples.removeFirst(min(samples.count, whisperSamples.count))
                whisperLoudSeconds = 0
            }
            if !whisperLastHypothesis.isEmpty {
                whisperLastHypothesis = ""
                whisperStableTicks = 0
                whisperPrevSegments.removeAll()
                onFinal?("", false)   // 잡음 가설로 떠 있던 잠정 말풍선 정리
            }
            return
        }

        // 전역 직렬화(§12 (whisper_공유)) — 다른 엔진이 공유 파이프로 전사 중이면 이번 틱 스킵(0.45초 뒤 재시도)
        guard Self.acquireTranscribe() else { return }
        whisperBusy = true
        whisperBusySince = Date()
        defer { Self.releaseTranscribe(); whisperBusy = false; whisperBusySince = nil; whisperBusyWarned = false }

        var options = DecodingOptions()
        options.task = .transcribe
        if whisperLanguages.count == 1 {
            options.language = whisperLanguages[0]    // 단일 세션 — 언어 고정
        } else {
            options.detectLanguage = true             // 쌍 세션 — 일단 자동 감지
        }
        // 문맥 조건화(A안) 비활성(2026-07-17 TTS 실측): turbo+promptTokens가 오류 없이 빈 결과를 반환 —
        // 같은 언어 확정 2건 후 해당 언어 자막이 통째로 블랙아웃(한·인니 양쪽 재현). decisions §7 개정 기록.
        // 재검토 조건: WhisperKit 프롬프트×turbo 호환 자체 실측 후. 치환 오류는 turbo 상향으로 해결 여부 채점 중.
        var results: [TranscriptionResult]
        do {
            results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        } catch {
            NSLog("VV whisper: 전사 실패 — %@", error.localizedDescription)   // 침묵 실패 금지
            return
        }

        // 쌍 클램프(2026-07-17 실측): 자동 감지가 선택된 두 언어 밖(영어·중국어 등)으로 새면
        // 직전 확정 언어(대화 관성) 또는 언어 1로 강제 재전사 — "선택한 언어에만 집중".
        if whisperLanguages.count > 1 {
            let detected = results.first?.language ?? ""
            if whisperLanguages.contains(detected) {
                whisperStickyLanguage = detected
            } else {
                var retry = options
                retry.detectLanguage = false
                retry.language = whisperStickyLanguage ?? whisperLanguages[0]
                if let clamped = try? await whisper.transcribe(audioArray: samples, decodeOptions: retry) {
                    results = clamped
                }
            }
        }
        // 창이 전사 중에 무효화됐으면 결과를 통째로 버린다 — 스냅샷 좌표로 트림하면 그새 들어온 발화를
        // 지우고(Route A 꼬리 보존도 무효), 발신하면 이미 꺼진 마이크에서 '나' 자막이 새로 뜬다.
        guard whisperLock.withLock({ audioGeneration }) == generation else {
            NSLog("VV whisper: 전사 중 창 무효화 — 결과 폐기(세대 %d)", generation)
            return
        }

        // 신뢰도 필터 — 소음·음악에서 "없는 대화"를 지어내는 환각 차단 (2026-07-17 실측):
        // Whisper 자체 지표로 저품질 세그먼트 폐기 — ①무음일 확률 높음 ②평균 로그확률 낮음 ③반복 압축비 과다
        var allSegments: [TranscriptionSegment] = []
        for result in results { allSegments.append(contentsOf: result.segments) }
        var trustedParts: [String] = []
        var trustedEnds: [Double] = []   // 세그먼트별 끝 시각 — LA 접두 확정의 트림 좌표
        var lastRenderedEnd = 0.0   // Route A(§8): 마지막으로 렌더된 신뢰 세그먼트 끝(초) — 미렌더 꼬리 보존 앵커
        for seg in allSegments {
            let trusted = seg.noSpeechProb < 0.5 && seg.avgLogprob > -1.1 && seg.compressionRatio < 2.4
            guard trusted else { continue }
            let cleaned = Self.cleanHallucinations(seg.text)
            // 단골 환각 문구(유튜브 마무리 멘트류)는 신뢰도 지표가 좋게 나와 필터 3종을 통과 — 문구 대조로 폐기 (2026-07-17 실측)
            if cleaned.isEmpty || Self.isStockHallucination(cleaned) { continue }
            trustedParts.append(cleaned)
            trustedEnds.append(Double(seg.end))
            lastRenderedEnd = max(lastRenderedEnd, Double(seg.end))
        }
        let text = trustedParts.joined(separator: " ")

        // ── LocalAgreement(세그먼트 단위 · 실험 · 기본 OFF) — 앞부분이 직전 틱과 그대로면 그만큼만 앞당겨 확정 ──
        // 창 전체가 일치하면 아래 기존 안정(stableTicks) 경로가 처리한다. 여기선 '앞 k개 일치 + 꼬리 변동 중'만.
        // 조건: k ≥ 1이고 접두가 문장 부호로 끝나거나 k ≥ 2(부호 없는 짧은 조각 단독 확정 방지). 트림은 k번째 세그먼트 끝까지 —
        // 렌더된 부분만 비우므로 경계 중복은 구조적으로 없고(Route A와 같은 성질), 어두 생존은 하네스가 판정한다.
        if Self.localAgreement, trustedParts.count >= 2, !whisperPrevSegments.isEmpty {
            var k = 0
            while k < min(trustedParts.count, whisperPrevSegments.count), trustedParts[k] == whisperPrevSegments[k] { k += 1 }
            if k >= 1, k < trustedParts.count {
                let prefix = trustedParts[..<k].joined(separator: " ")
                let prefixEnds = prefix.hasSuffix(".") || prefix.hasSuffix("?") || prefix.hasSuffix("!") || prefix.hasSuffix("…")
                if prefixEnds || k >= 2 {
                    let cutEnd = trustedEnds[k - 1]
                    let removeCount = min(Int(cutEnd * 16000), samples.count)
                    whisperLock.withLock {
                        whisperSamples.removeFirst(min(removeCount, whisperSamples.count))
                        // 꼬리는 방금 렌더된 신뢰 세그먼트 = 실제 발화. 발화량요구(0.7초) 아래로 내리면 게이트가 닫히는 순간
                        // 유보 guard가 꼬리를 통째로 폐기한다(2026-09-11 하네스 실측: 05의 4번째 문장 소실) → 하한 0.7 보장.
                        whisperLoudSeconds = max(0.7, whisperLoudSeconds - cutEnd)
                    }
                    let tail = trustedParts[k...].joined(separator: " ")
                    whisperPrevSegments = Array(trustedParts[k...])
                    whisperLastHypothesis = tail
                    whisperStableTicks = 0
                    NSLog("VV whisper: LA 접두 확정 %d/%d세그 \"%@…\" (트림 %.1f초)", k, trustedParts.count, String(prefix.prefix(12)), cutEnd)
                    onFinal?(prefix, false)
                    if !tail.isEmpty { onVolatile?(tail) }
                    return
                }
            }
        }
        whisperPrevSegments = trustedParts

        // 문장 확정 조건 — 배경 음악·소음이 있으면 '무음'이 영영 안 와서 확정이 지연되던 문제(2026-07-17 실측):
        //  ① 무음 0.7초  ② 전사 가설이 두 틱(0.45초×2=0.9초) 유지 = 발화 종료 신호(소음 무관)  ③ 6초 상한
        //  + 종결부호 인지(2026-07-17 오역 실측): 부호(.?!…) 없이 멈춘 가설은 문장 중 머뭇거림일 수 있어
        //    무음 1.5초까지 확정을 보류 — 문장 중간 싹둑(→오역)을 줄인다. 상한 6초는 절대 한도로 유지.
        if text == whisperLastHypothesis, text.count > 3 { whisperStableTicks += 1 } else { whisperStableTicks = 0 }
        whisperLastHypothesis = text
        let silentFor = Date().timeIntervalSince(lastLoudBufferAt)
        let endsSentence = text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") || text.hasSuffix("…")
        let shouldFinalize = samples.count > 16000 * 6
            || (endsSentence && (silentFor > 0.7 || whisperStableTicks >= 2))
            || (!endsSentence && silentFor > 1.5)

        if shouldFinalize {
            // 이어짐 힌트: 발화가 흐르는 중에 6초 상한이 자른 조각 = 다음 확정과 한 문장일 후보 (병합 판정 근거)
            let continuation = samples.count > 16000 * 6 && silentFor <= 0.7
            if !text.isEmpty {   // 계측: 확정 경로 판별(조기 분절·오역·병합 추적)
                NSLog("VV whisper: 확정 %d자 \"%@…\" (무음=%.1f초 안정=%d틱 버퍼=%.1f초 부호=%d 이어짐=%d)",
                      text.count, String(text.prefix(12)), silentFor, whisperStableTicks, bufferSec,
                      endsSentence ? 1 : 0, continuation ? 1 : 0)
            }
            // Route A(오버랩 포스트롤 — decisions §8): 전사한 창 전량이 아니라 '마지막 렌더 세그먼트 끝'까지만
            // 비우고, 그 이후 미렌더 꼬리(=다음 발화 어두)를 다음 창에 남긴다 → 경계 침범(첫 단어 삼킴) 방지.
            // 렌더된 부분만 지우므로 경계 단어 중복이 구조적으로 없음(dedup 조건 by construction 충족).
            // 단순화: 꼬리 보존 상한 2초(무음 꼬리 통째 보존·창 무한 성장 차단) — 소프트 변수 (경계_오버랩).
            // 신뢰 세그 0 또는 렌더가 창 전체를 덮으면 종전대로 전량 비움 폴백.
            let renderedSamples = Int(lastRenderedEnd * 16000)
            let removeCount = (renderedSamples > 0 && renderedSamples < samples.count)
                ? max(samples.count - 16000 * 2, renderedSamples)
                : samples.count
            whisperLock.withLock {
                whisperSamples.removeFirst(min(removeCount, whisperSamples.count))
                whisperLoudSeconds = 0   // 발화량도 창 단위로 재계상
            }
            // 확정과 함께 분류 잔상도 리셋 — 남겨둔 무음 꼬리(최대 2초)에 직전 발화의 잔상이 얹혀
            // '사람 말 0초'인 창이 발화량 0.3초를 채우고 전사에 투입되던 경로 차단(환각 재발 방지).
            // 발화가 이어지는 중이면 다음 분류(0.375초)가 곧 갱신하고, 그 사이는 프리롤 링이 보존한다.
            lastSpeechClassAt = .distantPast
            whisperLastHypothesis = ""
            whisperStableTicks = 0
            whisperPrevSegments.removeAll()
            onFinal?(text, continuation)   // 빈 텍스트도 발신 — UI가 잔류 잠정 말풍선을 지우는 신호(applyFinal이 처리)
        } else if !text.isEmpty {
            onVolatile?(text)
        }
    }

    /// 무음·소음에서 나오는 위스퍼 단골 환각 문구(유튜브 마무리 멘트 학습 잔재).
    /// 정규화(소문자·기호 제거) 후 **완전 일치만** 폐기 — 부분 일치 금지(진짜 발화 "감사합니다, 시작하죠" 보호).
    /// "terima kasih" 단독 등 실대화 표현은 절대 수록 금지(언어학자 검토).
    /// 단순화: 실측에서 새 문구가 확인될 때만 추가. 파일 전사 모드 도입 시 모드별 예외 재검토.
    private static let stockHallucinations: Set<String> = [
        // 인니·말레이
        "terimakasihkeranamenonton", "terimakasihsudahmenonton",
        "terimakasihtelahmenonton", "terimakasihkarenamenonton",
        "janganlupasubscribe", "sampaijumpadivideoselanjutnya",
        // 한국어
        "시청해주셔서감사합니다", "끝까지시청해주셔서감사합니다",
        "구독과좋아요부탁드립니다", "다음영상에서만나요",
        // 2026-09-11 SpectaLing 실물 사전에서 확인된 한국어 항목 4종 — 괄호 없는 비음성 라벨은
        // cleanHallucinations(괄호 전용)가 못 걷어내므로 완전 일치 사전이 유일한 방어선.
        "구독과좋아요부탁해요", "음악소리", "웃음소리", "박수소리",
        // 영어
        "thanksforwatching", "thankyouforwatching", "thankyousomuchforwatching",
        "pleasesubscribe", "dontforgettosubscribe", "seeyouinthenextvideo",
    ]

    static func isStockHallucination(_ text: String) -> Bool {   // 재전사도 같은 방어선(접근 수준만 완화)
        let key = String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return stockHallucinations.contains(key)
    }

    /// SoundAnalysis 분류 콜백 — '사람 말'(speech)만 관심. 콜백 스레드에서 시각만 기록(Date 단순 경합 허용).
    private final class SpeechClassObserver: NSObject, SNResultsObserving {
        private let onSpeech: () -> Void
        init(onSpeech: @escaping () -> Void) { self.onSpeech = onSpeech }
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult,
                  let speech = r.classification(forIdentifier: "speech"),
                  speech.confidence > 0.40 else { return }   // (분류_신뢰도) 소프트 변수
            // 0.55→0.40 (2026-07-25 실측): 원거리 발화는 신뢰도도 같이 떨어진다(1.5m 평균 0.58·2.0m 0.46).
            // 0.55에선 2.0m 검출이 25~51%로 무너지고 0.40이면 87~98%. 대가 없음 — 순수 소음 60초 오검출은
            // 0.55·0.40·0.30 전부 0%였다(임계를 더 낮춰도 이득이 없어 0.40에서 멈춤).
            onSpeech()
        }
    }

    /// Whisper 비음성 환각 제거 — 괄호 조각("(upbeat music)"·"[음악]")과 홀로 남은 괄호("[두 번째)까지 걷어냄.
    static func cleanHallucinations(_ text: String) -> String {
        // 특수 토큰 제거 — seg.text는 result.text와 달리 <|startoftranscript|>·<|ko|>·<|0.00|> 마커 포함(2026-07-17 실측)
        var s = text.replacingOccurrences(of: #"<\|[^|>]*\|>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]|\([^\)]*\)|♪[^♪]*♪|\*[^*]*\*"#,
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\[\]\(\)♪*]"#, with: "", options: .regularExpression)  // 짝 안 맞는 잔여 괄호·별표
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 전사기+분석기+결과 스트림 한 벌 생성. 결과 스트림이 끝나면(무음 오류 등) 자동 재시작.
    private func startRecognition(installAssets: Bool) async throws {
        inputContinuation?.finish()   // 이전 세션 입력 정리(재시작 경로)
        resultsTask?.cancel()

        // .fastResults: 정확도보다 첫 결과 속도 우선 — 실시간 자막의 핵심 옵션 (11.4초→1.0초 실측 개선)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])
        self.transcriber = transcriber

        if installAssets, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?("언어 모델 다운로드 중… (최초 1회)")
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.noAnalyzerFormat
        }
        analyzerFormat = format
        try? await analyzer.prepareToAnalyze(in: format)   // 예열(웜 상태면 빠름)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal { self?.onFinal?(text, false) } else { self?.onVolatile?(text) }
                }
            } catch {
                NSLog("VV recognizer: 결과 스트림 종료 — %@", error.localizedDescription)
            }
            // 무음 등으로 스트림이 끝나도 세션은 계속 — 인식기만 새로 만들어 이어붙임 (0구간 버그 수정)
            guard let self, !self.isStopping else { return }
            NSLog("VV recognizer: 자동 재시작")
            self.onRecognitionRestart?()   // 떠 있던 잠정 자막 확정 처리
            Task {
                do {
                    try await self.startRecognition(installAssets: false)
                    self.onStatus?("듣는 중")
                } catch {
                    self.onStatus?("인식 재시작 실패 — \(error.localizedDescription)")
                }
            }
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        try await analyzer.start(inputSequence: stream)
    }

    /// 발화 검출 — Whisper 경로의 게이트·무음 분절·발화량을 한 신호로 통일.
    /// 분류기(스펙트럼)가 주 판정, 초기화 실패 시에만 구 에너지 임계로 페일오픈.
    /// 게이트 개방과 발화량 누적이 같은 신호를 쓰므로 둘이 어긋나 창이 무한 성장하던 정지 경로가 구조적으로 닫힌다
    /// (구 코드: 게이트는 0.14로 열리는데 발화량은 0.17을 못 넘어 폐기도 전사도 안 되던 유보 루프).
    ///
    /// 유효 0.6초 = 분류 hop 0.375초 + 스케줄 지터 여유. 발화 중엔 hop마다 갱신돼 연속 유지되고,
    /// 발화가 끝나면 0.6초 안에 닫힌다 — 잔상이 길수록 ①무음 꼬리가 발화량을 채워 '사람 말 0초' 창이
    /// 전사에 투입되고(환각 재발) ②silentFor 기산점이 밀려 문장 확정이 늦어진다(검증 지적 2건).
    /// 잠깐의 문장 중 쉼으로 게이트가 닫혀도 프리롤 1초 링이 어두를 보존한다.
    private func speechDetected(rms: Float) -> Bool {
        guard rms > silenceFloor else { return false }   // 음소거·무신호는 어느 경로든 게이트 닫힘
        // 근접 전용 스트림(온라인 미팅의 '내 마이크')은 절대 임계를 유지한다 — 이 스트림의 확정은
        // 화자 분리 없이 무조건 '나'라서, 감도를 올리면 2m 밖 타인 발화가 '나' 자막으로 기록된다(§12).
        guard !nearFieldOnly else { return rms > whisperGate }
        return speechClassifierReady ? Date().timeIntervalSince(lastSpeechClassAt) < 0.6
                                     : rms > whisperGate
    }

    /// 잔여 전사 창 폐기 — '내 마이크' 토글 OFF처럼 즉시 멎어야 하는 경로용.
    /// 토글은 탭 입력만 끊어서, 이미 쌓인 창이 뒤늦게 전사돼 꺼짐 표시 상태에서 '나' 자막이
    /// 새로 뜨던 문제를 차단한다(민감한 대화 전에 끄는 용도라 정직성이 곧 기능).
    /// 세대를 올려 **이미 전사 중인 틱의 결과까지** 무효화한다 — 버퍼만 비우면 in-flight 전사가
    /// 완주해 그대로 자막을 발신한다(검증 지적). 가설 변수는 건드리지 않는다: 메인 스레드에서
    /// 쓰면 whisperTick과 락 없는 경합이 되고, 잠정 줄 정리는 이미 toggleMicCapture가 UI에서 한다.
    func discardPendingAudio() {
        whisperLock.withLock {
            whisperSamples.removeAll()
            whisperLoudSeconds = 0
            audioGeneration &+= 1
        }
        lastSpeechClassAt = .distantPast
    }

    /// 오디오 스레드에서 호출 — 레벨 계산 + 포맷 변환 + 분석기 공급.
    private func process(_ buffer: AVAudioPCMBuffer) {
        guard !isPaused else { return }
        lastBufferAt = Date()
        recorder?.write(raw: buffer)   // 원음 — 큐로 넘기기만 하고 즉시 반환(오디오 스레드 블로킹 금지)
        bufferCount += 1
        if bufferCount % 600 == 1 {   // 약 50초마다 심장박동 로그 (버퍼 흐름 계측)
            NSLog("VV audio: 버퍼 %d개 수신 중", bufferCount)
        }
        // 입력 레벨(RMS) — 무음 경고·미터의 원천 (청각으로 확인 불가한 사용자의 안전장치)
        var rms: Float = 0     // 발화량 게이트(whisper 적재부)에서도 사용 — 함수 스코프
        var voiced = false     // 이 버퍼가 '사람 말' 구간인가 (VAD 주 판정) — 적재부까지 전달
        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            rms = n > 0 ? sqrt(sum / Float(n)) : 0
            onLevel?(rms)   // 원시 RMS 전달 — ×18 증폭 포화로 미터가 상시 만렙이던 문제 수정 (스케일은 소비부에서)
            // 무음 분절·게이트를 한 신호(VAD)로 통일 — 구 코드는 각각 0.17·0.14의 절대 RMS였다.
            // 무음 분절까지 함께 옮겨야 한다: 게이트만 고치면 원거리 발화가 들어와도 rms>0.17을 못 넘어
            // silentFor가 계속 커진 채라 매 틱 조기 확정되고 문장이 토막난다(같은 뿌리의 2차 증상).
            voiced = speechDetected(rms: rms)
            if voiced {
                lastLoudBufferAt = Date()                                   // Whisper 무음 분절 판단
                gateOpenUntil = Date().addingTimeInterval(0.6)              // 게이트 열림 + 꼬리 여운
            }

            // 레벨 계측 — 5초마다 원시 RMS 분포 로그(소음 바닥 vs 발화 피크 실측 → 게이트 임계 데이터 보정)
            rmsWindow.append(rms)
            statBuffers += 1
            if Date() < gateOpenUntil { gateOpenBuffers += 1 }
            if Date().timeIntervalSince(lastLevelLogAt) > 5, !rmsWindow.isEmpty {
                let sorted = rmsWindow.sorted()
                let pct: (Double) -> Float = { sorted[Int(Double(sorted.count - 1) * $0)] }
                NSLog("VV rms: p10=%.4f p50=%.4f p90=%.4f peak=%.4f 게이트개방=%d/%d 적재=%.1f초",
                      pct(0.10), pct(0.50), pct(0.90), sorted[sorted.count - 1],
                      gateOpenBuffers, statBuffers, fedSeconds)
                rmsWindow.removeAll(keepingCapacity: true)
                gateOpenBuffers = 0; statBuffers = 0; fedSeconds = 0
                lastLevelLogAt = Date()
            }
        }

        guard let analyzerFormat else { return }
        // 변환기 지연 생성 — 소스(마이크/SCK) 포맷이 다르거나 도중 변해도 대응
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
            NSLog("VV audio: 변환기 생성 %@ → %@ (성공=%d)",
                  buffer.format.description, analyzerFormat.description, converter != nil ? 1 : 0)
        }
        guard let converter else {
            // 변환기 생성 실패 = 자막 전무의 침묵 원인 — 반드시 계측 (2026-07-17 VP 회귀 교훈)
            dropCount += 1
            if dropCount % 200 == 1 { NSLog("VV audio: 변환기 없음 — 버퍼 폐기 %d회", dropCount) }
            return
        }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        var fed = false
        var convError: NSError?
        converter.convert(to: out, error: &convError) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if convError == nil, out.frameLength > 0 {
            // 인식 음원 — 게이트 분기보다 앞이라 **게이트가 버린 소리까지** 남는다.
            // "앞사람이 분명 말했는데 자막이 없다"를 증거로 가릴 수 있는 유일한 지점(§13 실측 검증).
            recorder?.write(asr: out)
            audioClock += Double(out.frameLength) / analyzerFormat.sampleRate   // 자막↔화자 공통 시계
            // 화자 분리 공급 — 게이트와 무관하게 전체 오디오(라디오·타인 화자도 식별해야 숨길 수 있음)
            if diarizer != nil, let ch = out.floatChannelData?[0] {
                diarLock.lock()
                if diarClockOrigin < 0 {   // 첫 공급 = 디아라이저 프레임 0의 절대(audioClock) 시각
                    diarClockOrigin = audioClock - Double(out.frameLength) / analyzerFormat.sampleRate
                }
                diarSamples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
                diarLock.unlock()
            }
            switch recognizerKind {
            case .apple:
                inputContinuation?.yield(AnalyzerInput(buffer: out))
            case .whisper:
                // 음성 분류 공급 — 게이트와 무관하게 전체 오디오(분류 결과가 게이트의 판단 근거)
                if let analyzer = soundAnalyzer {
                    analyzer.analyze(out, atAudioFramePosition: snFramePos)
                    snFramePos += AVAudioFramePosition(out.frameLength)
                }
                // 노이즈 게이트 + 프리롤: 게이트가 열리는 순간 직전 1초(링)를 선주입 —
                // 임계를 넘기 전에 발화된 첫 음절 소실("바탐공항 관계자 분이" — 2026-07-17 원문 대조 실측) 방지
                let gateOpen = Date() < gateOpenUntil
                if gateOpen, let ch = out.floatChannelData?[0] {
                    whisperLock.lock()
                    if !whisperGateWasOpen, !whisperPreRoll.isEmpty {
                        whisperSamples.append(contentsOf: whisperPreRoll)
                        whisperPreRoll.removeAll(keepingCapacity: true)
                    }
                    whisperSamples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
                    // 분류기가 살아 있을 때만 voiced 단독으로 누적한다. 페일오픈(분류기 불가)에서 voiced는
                    // rms>0.14로 축약되므로, 그대로 쓰면 구 2단 방어(적재 0.14 / 발화량 0.17)가 1단으로
                    // 무너져 팬·에어컨 소음(0.15)만으로 전사 자격이 생긴다 — 그 모드에선 0.17을 유지한다.
                    // ⚠️ `!nearFieldOnly`가 빠지면 안 된다: 근접 전용 스트림의 voiced도 에너지(0.14)로
                    // 축약되므로, 분류기가 살아 있다는 이유로 단락되면 2단이 0.14 1단으로 무너진다.
                    // 실측(하네스 근접전용 모드): 그 상태에서 1m 거리 타인 발화가 0% → 76%로 전사에 도달했다.
                    if voiced, (speechClassifierReady && !nearFieldOnly) || rms > 0.17 {
                        whisperLoudSeconds += Double(out.frameLength) / analyzerFormat.sampleRate
                    }
                    // 단순화: 창 상한 30초. 전사가 행(hang)하거나 공유 락 경쟁으로 틱이 트림에 도달하지
                    // 못하는 동안 창이 무한 성장하던 경로 차단(메모리·전사 비용이 서로를 키우는 되먹임).
                    // 행 자체의 복구(전사 타임아웃·엔진 재시작)는 미구현 — 실사용에서 행이 관측되면 승격.
                    if whisperSamples.count > 16000 * 30 {
                        whisperSamples.removeFirst(whisperSamples.count - 16000 * 30)
                        audioGeneration &+= 1   // 앞을 잘랐으니 진행 중 전사의 스냅샷 좌표는 무효
                    }
                    whisperLock.unlock()
                    fedSeconds += Double(out.frameLength) / analyzerFormat.sampleRate   // 계측: 전사 버퍼 적재량
                } else if let ch = out.floatChannelData?[0] {
                    whisperPreRoll.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
                    if whisperPreRoll.count > 16000 { whisperPreRoll.removeFirst(whisperPreRoll.count - 16000) }
                }
                whisperGateWasOpen = gateOpen
            }
        }
    }

    func pause() {
        isPaused = true                        // 시스템 오디오는 버퍼 드롭으로 일시정지
        if audioEngine.isRunning { audioEngine.pause() }
    }

    func resume() throws {
        isPaused = false
        if !usingSystemTap, !audioEngine.isRunning { try audioEngine.start() }
    }

    func stop() async {
        isStopping = true                      // 자동 재시작 차단
        recorder?.finish()                     // WAV 헤더 확정 — 이후 도착 버퍼는 없다(탭 제거가 뒤따름)
        recorder = nil
        if !usingSystemTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        #if os(macOS)
        await systemTap?.stop()
        systemTap = nil
        #endif
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        whisperTask?.cancel()
        diarTask?.cancel()
        diarizer?.cleanup()
        diarizer = nil
        whisper = nil
        analyzer = nil
        transcriber = nil
        converter = nil
    }
}
