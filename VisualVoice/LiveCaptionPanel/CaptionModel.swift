import SwiftUI
import AVFoundation

/// decisions.md §6 확정 팔레트 + 앱 셸 색(다크 단일 테마).
enum Theme {
    // 자막 · 화자
    static let ink       = Color(hex: 0xEEF1F6)
    static let ink2      = Color(hex: 0x9AA3B2)
    static let ink3      = Color(hex: 0x828B9C)   // 2026-07-17 AA 보정(구 0x6B7180은 소형 텍스트 4.5:1 미달)
    static let accent    = Color(hex: 0x4CC2D6)
    static let accentDim = Color(hex: 0x4CC2D6).opacity(0.14)
    static let rec       = Color(hex: 0xF26D6D)
    static let trans     = Color(hex: 0x8FC3D6)
    static let good      = Color(hex: 0x5BC8A0)
    static let warn      = Color(hex: 0xFEBC2E)   // 경고(노랑) — 리터럴 8곳 단일화(2026-09-11, 규칙 4)
    static let me        = Color(hex: 0x7AA2F7)
    static let p1        = Color(hex: 0x5BC8A0)
    static let p2        = Color(hex: 0xE890A8)
    static let p3        = Color(hex: 0xBCA0EC)
    static let hair      = Color.white.opacity(0.08)
    // 앱 셸
    static let bgSide    = Color(hex: 0x0E1016)
    static let bgMain    = Color(hex: 0x14171F)
    static let card      = Color(hex: 0x1B1F29)
    static let card2     = Color(hex: 0x222634)
}

struct AppLanguage: Hashable, Identifiable {
    let code: String
    let name: String
    let short: String
    var id: String { code }
    static let ko   = AppLanguage(code: "ko", name: "한국어", short: "한")
    static let en   = AppLanguage(code: "en", name: "영어", short: "영")
    static let indo = AppLanguage(code: "id", name: "인도네시아어", short: "인니")
    static let all: [AppLanguage] = [ko, en, indo]

    /// STT 로케일 (KO/EN=SpeechTranscriber 지원 확인, ID=미지원 → WhisperKit 경로는 다음 스파이크)
    var sttLocale: String {
        switch code { case "ko": return "ko-KR"; case "en": return "en-US"; default: return "id-ID" }
    }
}

/// 세션 언어 — 단일(자막만) 또는 쌍(자막+번역) (decisions.md §2, 2026-07-17 최종).
/// 근본 목적은 청각 지원: 같은 언어(특히 한↔한) 자막·녹취가 1순위, 번역은 옵션.
/// 쌍의 방향(A→B/B→A)은 발화별 자동 감지라 순서 개념 없음.
struct LanguagePair: Hashable, Identifiable {
    let a: AppLanguage
    let b: AppLanguage
    var id: String { "\(a.code)-\(b.code)" }
    var isSingle: Bool { a == b }                    // 단일 언어 = 자막만, 번역 없음
    var label: String { isSingle ? a.name : "\(a.name) ⇄ \(b.name)" }
    var short: String { isSingle ? a.short : "\(a.short)↔\(b.short)" }

    /// 기본값 — 1순위 유스케이스(한국인끼리 대화 청각 지원).
    static let koOnly = LanguagePair(a: .ko, b: .ko)
}

enum CaptureMode: Identifiable, CaseIterable {
    case inPerson, onlineMeeting, micPlusSystem, file
    var id: Self { self }
    var title: String {
        switch self {
        case .inPerson:      return "대면 대화"
        case .onlineMeeting: return "온라인 미팅"
        case .micPlusSystem: return "마이크 + 시스템"
        case .file:          return "파일 전사"
        }
    }
    var desc: String {
        switch self {
        case .inPerson:      return "앞에 있는 사람과의 대화를 마이크로 실시간 자막."
        case .onlineMeeting: return "줌·팀즈 등 상대 소리와 내 발화를 함께 실시간 자막."
        case .micPlusSystem: return "대면과 원격이 섞인 자리. 나·상대 자동 구분."
        case .file:          return "녹음·영상 파일을 불러와 자막·회의록으로."
        }
    }
    var symbol: String {
        switch self {
        case .inPerson:      return "mic.fill"
        case .onlineMeeting: return "display"
        case .micPlusSystem: return "headphones"
        case .file:          return "doc.fill"
        }
    }
    var isPrimary: Bool { self == .inPerson }
}

/// 화자 — 마이크=나(로컬), 시스템 오디오=상대 N(원격). decisions.md §3·§6.
/// unlabeled: 단일 마이크 실전사에서 화자 분리 배선 전 상태 — "나"로 사칭하지 않음(정직성).
enum Speaker: Hashable, Codable {
    case me
    case remote(Int)
    case unlabeled
    var label: String {
        switch self {
        case .me: return "나"
        case .remote(let n): return "상대 \(n)"
        case .unlabeled: return "화자"
        }
    }
    var color: Color {
        switch self {
        case .me: return Theme.me
        case .remote(let n):
            switch n {
            case 1: return Theme.p1
            case 2: return Theme.p2
            default: return Theme.p3
            }
        case .unlabeled: return Theme.ink2
        }
    }
}

struct CaptionLine: Identifiable, Codable {
    var id = UUID()
    var speaker: Speaker
    var source: String
    var translation: String
    /// AI 재번역(종료 후 내장 LLM) — 실시간 translation은 절대 불변(조용한 고쳐쓰기 금지, §11.4).
    /// nil = 재번역 안 됨(실시간본 표시·마커 없음). CodingKeys 없는 자동합성이라 구 JSON 안전.
    var refinedTranslation: String? = nil
    var timecode: String
    var isVolatile: Bool = false        // 잠정(아직 확정 안 된 현재 발화)
    var speakerUncertain: Bool = false  // 화자 추정 불확실 → 점선 칩 + ?
    var isTyped: Bool = false           // 타이핑 발화(Type-to-Speak) — ⌨️ 배지 + 읽어주기
    var fluidSpeaker: Int? = nil        // 화자 분리 트랙 번호(LS-EEND) — 나 지정·숨김의 키
    var clockStart: Double? = nil       // 오디오 시계(초) — 화자 세그먼트 정렬용
    var clockEnd: Double? = nil
    /// 사용자가 직접 지정한 화자 — 라이브 backfill·배치 재계산이 덮어쓰지 않는다(§3 조용한 고쳐쓰기 금지 · 2026-09-11 B②).
    /// ⚠️ 저장은 Optional(`userSetFlag`)로 — 합성 Decodable은 `Bool = false` 기본값을 **쓰지 않고** 키 부재를 오류로 낸다.
    /// (2026-09-11 실측: 이 필드를 Bool로 넣자 구 21건 로드가 통째로 실패해 샘플이 부활했다. Optional만 decodeIfPresent.)
    var speakerIsUserSet: Bool {
        get { userSetFlag ?? false }
        set { userSetFlag = newValue }
    }
    var userSetFlag: Bool? = nil   // private이면 멤버와이즈 init이 private이 된다 — 직접 쓰지 말고 speakerIsUserSet 사용

    enum CodingKeys: String, CodingKey {
        case id, speaker, source, translation, refinedTranslation, timecode, isVolatile, speakerUncertain, isTyped
        case fluidSpeaker, clockStart, clockEnd
        case userSetFlag = "speakerIsUserSet"
    }

    /// 한↔인니 양방향 예시 (언어 쌍, decisions.md §2·§6).
    static let sampleLive: [CaptionLine] = [
        .init(speaker: .me,
              source: "자카르타 팀은 화요일 10시가 괜찮을까요?",
              translation: "Apakah tim Jakarta oke dengan hari Selasa jam 10?",
              timecode: "00:12:31"),
        .init(speaker: .remote(1),
              source: "Ya, jam 10 lebih baik untuk kami.",
              translation: "네, 저희는 10시가 더 좋아요.",
              timecode: "00:12:38"),
        .init(speaker: .remote(1),
              source: "Baik, saya akan kirim undangannya sekarang",
              translation: "좋아요, 제가 지금 초대장을 보낼게요",
              timecode: "00:12:47",
              isVolatile: true),
    ]

    /// 한국어 단일(자막만) 예시 — 1순위 유스케이스: 같은 언어 대화의 청각 지원.
    static let sampleKoreanOnly: [CaptionLine] = [
        .init(speaker: .remote(1),
              source: "지난주에 말씀하신 견적서 검토해 봤는데요.",
              translation: "", timecode: "00:08:12"),
        .init(speaker: .me,
              source: "네, 어떤 부분이 걸리셨어요?",
              translation: "", timecode: "00:08:18"),
        .init(speaker: .remote(1),
              source: "3번 항목 단가가 처음 얘기했던 것보다 높아서요. 이 부분 조정이 가능한지 확인 부탁드려요",
              translation: "", timecode: "00:08:24",
              isVolatile: true),
    ]

    /// 세션 상세 > 녹취록 탭 예시 (확정 발화만, 타임코드·화자 라벨 전체 표기).
    static let sampleTranscript: [CaptionLine] = [
        .init(speaker: .me,
              source: "안녕하세요, 오늘 킥오프 일정 조율 때문에 연락드렸어요.",
              translation: "Halo, saya menghubungi Anda untuk mengatur jadwal kickoff hari ini.",
              timecode: "00:00:04"),
        .init(speaker: .remote(1),
              source: "Halo! Ya, kami sudah menunggu kabar dari Anda.",
              translation: "안녕하세요! 네, 저희도 연락 기다리고 있었어요.",
              timecode: "00:00:11"),
        .init(speaker: .me,
              source: "자카르타 팀은 화요일 10시가 괜찮을까요?",
              translation: "Apakah tim Jakarta oke dengan hari Selasa jam 10?",
              timecode: "00:12:31"),
        .init(speaker: .remote(1),
              source: "Ya, jam 10 lebih baik untuk kami.",
              translation: "네, 저희는 10시가 더 좋아요.",
              timecode: "00:12:38"),
        .init(speaker: .remote(2),
              source: "Kontrak drafnya sebaiknya kita review sebelum meeting.",
              translation: "계약 초안은 미팅 전에 검토하는 게 좋겠어요.",
              timecode: "00:14:02",
              speakerUncertain: true),
        .init(speaker: .me,
              source: "좋습니다. 그럼 초대장은 그쪽에서 보내주시겠어요?",
              translation: "Baik. Kalau begitu, bisakah undangannya dikirim dari pihak Anda?",
              timecode: "00:15:19"),
        .init(speaker: .remote(1),
              source: "Tentu, saya akan kirim undangannya hari ini.",
              translation: "물론이죠, 오늘 초대장을 보내드릴게요.",
              timecode: "00:15:27"),
    ]
}

/// AI 재번역 상태 — MinutesState 4-케이스 규약 복제(침묵 실패 금지, §11.4).
/// 진행률(n/N)은 영속 대상이 아니라 AppModel @Published(라이브 신호)로만.
enum RefinementState: Codable, Equatable {
    case refining
    case ready
    case unavailable(String)   // 사유 문구 그대로 배너 노출
}

struct Session: Identifiable, Codable {
    var id = UUID()
    var title: String
    var dateLabel: String
    var pairShort: String
    var segments: Int
    var duration: String
    var dotColor: Color = Theme.rec        // 저장 제외(Color 비직렬화) — 복원 시 기본색
    var preview: String
    var transcript: [CaptionLine]? = nil   // 실녹취 — JSON으로 영구 저장 (2026-07-17)
    var minutes: MinutesState = .none      // 회의록 — 세션 정지 시 온디바이스 생성
    var refinement: RefinementState? = nil // AI 재번역 — nil=미시도(구 세션 하위호환, decodeIfPresent 안전)
    // 2026-09-11 (SpectaLing 대조 §15.3 ⑥ — 세션 메타 부재): 전부 Optional = 구 JSON은 decodeIfPresent로 안전.
    var createdAt: Date? = nil             // 진짜 날짜. 구 세션은 nil → 녹음 파일 생성시각으로 복구 시도, 못 하면 '날짜 미상'
    var engineLabel: String? = nil         // 어느 인식기가 만든 세션인가 — §14 분석 루프의 사후 판별 근거
    var modelUsed: String? = nil
    var notes: [String]? = nil             // 세션 중 열화 사유(마이크 실패·오디오 끊김·녹음 실패·번역 실패) — 영속 고지
    var retranscript: [CaptionLine]? = nil // 녹음 재전사 대본(B④) — 라이브 자막과 대조하는 '정답 대본'. 원 transcript는 불변
    var retranscriptInfo: String? = nil    // 재전사 조건(모델·파일·줄 수)

    enum CodingKeys: String, CodingKey {
        case id, title, dateLabel, pairShort, segments, duration, preview, transcript, minutes, refinement
        case createdAt, engineLabel, modelUsed, notes, retranscript, retranscriptInfo   // ⚠️ 새 필드는 반드시 여기 등재 — 빠지면 조용히 저장 안 됨
    }

    /// 표시용 날짜 — 저장된 문자열이 아니라 createdAt에서 파생. 구 세션(nil)은 '날짜 미상'으로 정직 표기.
    /// (구 코드는 "오늘" 리터럴을 저장해 21건 전부 '오늘'로 표시됐다 — CLAUDE.md 날짜 결함.)
    var displayDate: String { createdAt.map { Session.dateLabel(for: $0) } ?? "날짜 미상" }
    var isLegacyUndated: Bool { createdAt == nil }

    static func dateLabel(for d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return "오늘 \(hm.string(from: d))" }
        if cal.isDateInYesterday(d) { return "어제 \(hm.string(from: d))" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(d, equalTo: now, toGranularity: .year) ? "M. d HH:mm" : "yyyy. M. d HH:mm"
        return f.string(from: d)
    }

    static let samples: [Session] = [
        .init(title: "팀 킥오프 미팅", dateLabel: "오늘 14:20", pairShort: "한↔영",
              segments: 42, duration: "12:47", dotColor: Theme.me,
              preview: "그럼 다음 주 화요일에 킥오프 미팅을 잡을까요? — Tuesday works, but can we…",
              createdAt: Date().addingTimeInterval(-3600)),
        .init(title: "자카르타 파트너 콜", dateLabel: "어제 10:05", pairShort: "한↔인니",
              segments: 28, duration: "24:10", dotColor: Theme.p1,
              preview: "자카르타 팀은 화요일 10시가 괜찮을까요? — Ya, jam 10 lebih baik…",
              createdAt: Date().addingTimeInterval(-86400)),
        .init(title: "제품 리뷰 (대면)", dateLabel: "7. 15", pairShort: "한↔영",
              segments: 51, duration: "33:02", dotColor: Theme.p2,
              preview: "이 화면 흐름은 사용자가 헷갈릴 수 있어요 — Let's simplify the onboarding…",
              createdAt: Date().addingTimeInterval(-86400 * 3)),
        .init(title: "벤더 견적 협의", dateLabel: "7. 14", pairShort: "영↔인니",
              segments: 19, duration: "15:38", dotColor: Theme.me,
              preview: "Can you share the revised quote? — Tentu, saya kirim sekarang…",
              createdAt: Date().addingTimeInterval(-86400 * 4)),
    ]
}

/// 세션 영구 저장 — Application Support/VisualVoice/sessions.json (2026-07-17).
/// ponytail: 전량 JSON 재기록 — 세션 수백 개 규모까지는 충분, 병목이 실측되면 개별 파일 분리.
enum SessionStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisualVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    /// 로드 실패 고지 — 셸 배너. (2026-09-11 실측: 스키마 실수 하나로 디코딩이 깨지자 샘플이 시드됐고,
    /// 그 상태에서 무엇이든 바꾸면 샘플이 진짜 기록 21건을 **덮어쓸** 경로였다. 이제 실패하면 원본을 옆에 보존하고 빈 목록으로 시작한다.)
    static var loadError: String?

    static func load() -> [Session]? {
        // 파일이 없으면 최초 실행 → nil(샘플 시드). 파일이 있으면 빈 배열이어도 그대로 존중 —
        // 전부 삭제 후 []가 저장됐을 때 재실행하면 샘플이 부활하던 버그 수정 (2026-07-18).
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            loadError = "저장된 세션 기록 파일을 읽지 못했습니다 — 기록은 지우지 않았습니다."
            return []
        }
        var sessions: [Session]
        do { sessions = try JSONDecoder().decode([Session].self, from: data) }
        catch {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("sessions.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("VV store: 세션 파일 디코딩 실패 — %@ (원본 보존 %@)", "\(error)", backup.lastPathComponent)
            loadError = "저장된 세션 기록을 읽지 못해 원본을 \(backup.lastPathComponent)로 보존했습니다. 앱 업데이트 문제일 수 있어요 — 기록은 지워지지 않았습니다."
            return []
        }
        // 과거 저장된 빈 세션(대화 없음) 일괄 정리 — 정지 시 미저장으로 바뀌기 전 잔재 청소 (2026-07-17)
        sessions.removeAll { $0.segments == 0 && ($0.transcript ?? []).isEmpty }
        // 생성 중 앱이 종료된 세션 — '작성 중'으로 영영 남지 않게 정직하게 표기
        for i in sessions.indices where sessions[i].minutes == .generating {
            sessions[i].minutes = .unavailable("회의록 생성 중 앱이 종료되었습니다. 녹취록은 보존되어 있습니다.")
        }
        // AI 재번역 중 종료 — '재번역 중' 영구 매달림 방지(동일 규약 미러, §11.4)
        for i in sessions.indices where sessions[i].refinement == .refining {
            sessions[i].refinement = .unavailable("AI 재번역 중 앱이 종료되었습니다 — 실시간 번역을 표시하고 있어요.")
        }
        // 날짜 복구(2026-09-11 · 1회 마이그레이션): createdAt이 없는 구 세션은 녹음 WAV의 생성 시각이 유일한
        // 진짜 시작 시각이다(파일명 = 세션 UUID). 녹음이 없으면 nil 그대로 → 화면이 '날짜 미상'으로 정직 표기.
        for i in sessions.indices where sessions[i].createdAt == nil {
            if let d = SessionRecorder.earliestFileDate(for: sessions[i].id) {
                sessions[i].createdAt = d
                NSLog("VV store: 날짜 복구 %@ ← 녹음 생성시각", sessions[i].title)
            }
        }
        return sessions
    }

    /// 저장 — 실패 사유를 돌려준다(nil=성공). 구 코드는 `try? write`로 쓰기 실패를 삼켰다(2026-09-11 §15.3 ④).
    @discardableResult
    static func save(_ sessions: [Session]) -> String? {
        NSLog("VV store: 저장 %d건", sessions.count)   // 계측 — 2026-07-17 빈 배열([]) 저장 미스터리 추적
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            NSLog("VV store: 세션 저장 실패 — %@", error.localizedDescription)   // 침묵 실패 금지
            return error.localizedDescription
        }
    }
}

/// 라이브 고주파 신호 전용 — 이 객체를 관찰하는 작은 뷰(시계·미터·배너)만 재렌더된다.
@MainActor
final class LiveMetrics: ObservableObject {
    @Published var meterStep: Int = 0            // 레벨 미터 칸 수 0~7 (칸 변화 시에만 갱신)
    @Published var micMeterStep: Int = 0         // 온라인 미팅 마이크 스트림 미터 — 2계통 표시 (decisions §12)
    @Published var elapsed: TimeInterval = 0
    @Published var silenceSeconds: Int = 0
    @Published var firstCaptionDelay: Double?    // 실측 계기판: 말소리 감지 → 첫 자막

    var elapsedLabel: String { Self.format(elapsed) }

    func reset() {
        meterStep = 0; micMeterStep = 0; elapsed = 0; silenceSeconds = 0; firstCaptionDelay = nil
    }

    nonisolated static func format(_ t: TimeInterval) -> String {   // 순수 함수 — 비메인 액터(재전사)도 사용
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 앱 전역 상태 — 세션 상태 머신(안전③) + 마이크 STT 배선 + 무음 감지(안전②).
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Hashable { case home, live, detail, settings, archive }
    /// 세션 상태 머신 — 덮어쓰기·실수 종료 방지의 근간 (워게임 usability §1)
    enum SessionState { case idle, preparing, recording, paused }

    @Published var screen: Screen = .home
    // 온보딩 — 첫 실행에만(hasOnboarded 플래그). decisions §5 · 목업 컨펌 2026-07-18.
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "vv.hasOnboarded")
    func finishOnboarding() { UserDefaults.standard.set(true, forKey: "vv.hasOnboarded"); showOnboarding = false }
    /// 세션 언어 — 마지막 선택 유지(UserDefaults · 2026-09-11 §2 개정). "기본값 = 한국어·한국어"는 최초 실행 기본값.
    @Published var pair: LanguagePair = AppModel.loadPair() {
        didSet { UserDefaults.standard.set([pair.a.code, pair.b.code], forKey: "vv.pair") }
    }
    private static func loadPair() -> LanguagePair {
        guard let codes = UserDefaults.standard.stringArray(forKey: "vv.pair"), codes.count == 2,
              let a = AppLanguage.all.first(where: { $0.code == codes[0] }),
              let b = AppLanguage.all.first(where: { $0.code == codes[1] }) else { return .koOnly }
        return LanguagePair(a: a, b: b)
    }
    @Published var sessions = Session.samples {
        didSet {   // 삽입·삭제·회의록 갱신 모두 즉시 영구화 — 쓰기 실패는 배너로(침묵 실패 금지, 2026-09-11)
            let err = SessionStore.save(sessions)
            if err != saveError { Task { @MainActor in self.saveError = err } }   // didSet 안 @Published 직접 쓰기 회피
        }
    }
    @Published var saveError: String?             // sessions.json 쓰기 실패 사유 — 셸 상단 배너(nil=정상)
    @Published var homeNotice: String?            // 세션 종료 후 홈 1회 고지(무자막 세션 등) — 다음 start()에서 소멸
    private var sessionNotes: [String] = []       // 세션 중 열화 사유 수집 → Session.notes(영속 고지)
    private var sessionStartedAt: Date?
    private var sessionUsesWhisper = false
    private var audioKicks = 0                    // 오디오 끊김 에피소드 수 — notes용
    private var audioBroken = false
    @Published var liveTitle = "자카르타 파트너 콜"
    @Published var liveLines = CaptionLine.sampleLive
    @Published var selectedSession: Session?

    // 라이브 세션 상태 (저주파 — 화면 전환·상태 변화만)
    @Published var sessionState: SessionState = .idle
    @Published var statusMessage: String?         // 준비/오류 안내

    /// 세션 음원 녹음 상태 — 청각으로 확인할 수 없으므로 세션 내내 화면에 떠 있어야 한다(decisions §14).
    enum RecordingStatus: Equatable { case off, on, failed(String) }
    @Published var recordingStatus: RecordingStatus = .off
    /// 세션 ID를 시작 시점에 확정한다 — 녹음 파일 이름의 근거. 종료 시점에 만들면 파일과 세션을
    /// 잇는 rename이 필요해지고, 그 rename 실패가 곧 영구 고아가 된다(워게임 §0-⑦, QC 조건).
    private var pendingSessionID: UUID?

    // 팝아웃 자동 표시(창 가림 시) — decisions §8 / wargame `[2026-07-18]_popout_auto_show`
    @Published var mainWindowOccluded = false     // 메인 창이 가려지거나 최소화됨
    @Published var popoutOpen = false             // 팝아웃 창 열림(팝아웃 onAppear/onDisappear가 갱신)
    var popoutAutoShown = false                   // 자동으로 띄움(상단 '자동' 배지·자동닫기 판정)
    var popoutUserMoved = false                   // 사용자가 옮기거나 크기 조정 → 자동 닫기 억제
    var popoutManuallyClosed = false              // 세션 중 수동으로 닫음 → 그 세션 재표시 억제

    /// 고주파 신호(레벨·시계·무음)는 별도 객체 — AppModel을 초당 십수 회 갱신하면
    /// 사이드바·자막 전 줄이 매번 재렌더되어 중간 버벅임 발생 (2026-07-17 실측 → 분리)
    let metrics = LiveMetrics()

    /// 확정 자막 → 상대 언어 번역 (쌍 세션 전용, Translation framework)
    let translator = TranslationCoordinator()

    init() {
        // 저장분 복원 — 없으면 샘플(최초 실행 시드).
        // 녹음 고아 청소는 **복원에 성공했을 때만** — 실패 상태에서 돌리면 살아 있는 녹음을 전량 지운다
        // (세션이 폐기·삭제된 뒤 남은 파일과 크래시 잔재를 한 번에 정리, decisions §14).
        if let saved = SessionStore.load() { sessions = saved }
        storeNotice = SessionStore.loadError
        SessionRecorder.repairInterrupted()   // 지난번 크래시로 마감 못 한 녹음 살리기(삭제는 하지 않는다)
    }
    @Published var storeNotice: String?           // 세션 파일 로드 실패 고지(셸 배너) — 저장 성공으로 지워지지 않는다

    // ── 화자 분리 상태 (워게임 2026-07-17 확정: 수동 '나' 지정 · 자막만 숨김) ──
    private var speakerSegments: [MicTranscriptionEngine.SpeakerSegment] = []
    private var tentativeSegments: [MicTranscriptionEngine.SpeakerSegment] = []
    private var speakerMap: [Int: Speaker] = [:]
    private var nextRemoteNumber = 1
    private var lastFinalClock: Double = 0            // main 스트림 전용 — 디아라이저 정렬 시계 (마이크 줄은 시계 미사용)
    @Published var mySpeakerIndex: Int?
    @Published var hiddenSpeakerIndexes: Set<Int> = []

    // ── 온라인 미팅 마이크 동시 캡처 (decisions §12 · 2026-07-24) ──
    // 스트림별 자막 상태 — main(주 엔진: 대면=마이크/온라인 미팅=시스템)·myMic(온라인 미팅의 내 발화 부가 스트림).
    // 병합·잠정은 같은 스트림끼리만(마이크 확정이 시스템 확정에 오병합되는 크로스 병합 차단 — Blueprint §4).
    enum CapStream: Hashable { case main, myMic }
    private struct StreamState {
        var volatileID: UUID?
        var lastFinalAt = Date.distantPast        // 문장 병합 판정용 — 직전 확정의 벽시계
        var lastFinalContinuation = false          // 직전 확정이 6초 상한으로 발화 중간에서 잘렸는가
        var lastFinalLineID: UUID?                 // 병합 대상(이 스트림의 직전 확정 줄)
    }
    private var streamStates: [CapStream: StreamState] = [.main: StreamState()]
    private var micEngine: MicTranscriptionEngine?     // nil = 단일 소스 세션
    @Published private(set) var dualCaptureSession = false   // 온라인 미팅 = 토글·미터 2계통 표시
    @Published var micCaptureOn = true                 // "내 마이크" 토글 — 세션마다 켜짐 기본 (§12)
    @Published var micBannerText: String?              // 마이크 소프트 실패 배너(권한 거부 등 — 세션은 계속)
    @Published var speakerOutputActive = false         // 내장 스피커 출력 감지 — 이중 자막 경고 배너
    private var ttsSpeaking = false                    // 읽어주기 재생 중 — 토글과 합성해 micMuted 결정
    private var tickCount = 0                          // 스피커 출력 폴링 주기(5초) 계수

    /// 라이브 표시용 — 숨긴 화자 제외(녹취록에는 전량 보존, QC 데이터 손실 제로)
    var visibleLiveLines: [CaptionLine] {
        liveLines.filter { line in
            guard let idx = line.fluidSpeaker else { return true }
            return !hiddenSpeakerIndexes.contains(idx)
        }
    }

    private var engine: MicTranscriptionEngine?
    private var ticker: Timer?
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date?
    private var lastVoiceAt = Date()
    private var lastLoudAt = Date.distantPast     // 뚜렷한 발화(높은 임계)의 마지막 시각
    private var firstVoiceAt: Date?               // 지연 측정 기점 — 첫 자막을 만든 발화의 시작

    /// 현재 경과(내부 계산용 — published 아님)
    private var elapsedNow: TimeInterval {
        accumulated + (resumedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// 앱 실행 직후 기본 언어 모델 사전 설치+예열 (AppShellView .task에서 1회 호출)
    func preheatDefaultLanguage() {
        let locale = pair.a.sttLocale
        Task.detached(priority: .utility) {
            await MicTranscriptionEngine.preheatAssets(localeIdentifier: locale)
        }
    }

    /// 무음 경고 임계 — 잠정 기본 15초 (변수 `(무음경고임계초)` — 실사용 후 조정)
    var showSilenceWarning: Bool { sessionState == .recording && metrics.silenceSeconds >= 15 }

    func start(_ mode: CaptureMode) {
        // 진행 중 세션 존재 → 덮어쓰지 않고 라이브로 복귀 (워게임: start() 무조건 덮어쓰기 제거)
        guard sessionState == .idle else { screen = .live; return }
        // 대면 대화=마이크 / 온라인 미팅=시스템 오디오(SCK)+마이크 병행(decisions §12). 나머지 2종은 다음 스파이크 (타일 비활성)
        let source: MicTranscriptionEngine.Source
        switch mode {
        case .inPerson:      source = .mic
        case .onlineMeeting: source = .systemAudio
        default: return
        }

        liveTitle = mode.title
        liveLines = []
        homeNotice = nil
        sessionNotes = []
        audioKicks = 0; audioBroken = false
        sessionStartedAt = Date()
        streamStates = [.main: StreamState()]
        dualCaptureSession = (mode == .onlineMeeting)
        micCaptureOn = true                       // §12: 세션마다 켜짐 기본
        micBannerText = nil
        speakerOutputActive = false
        ttsSpeaking = false
        metrics.reset()
        firstVoiceAt = nil
        // 세션 음원 녹음 — ID를 지금 확정한다(파일 이름의 근거이자 stopSession이 그대로 쓸 세션 ID).
        let sid = UUID()
        pendingSessionID = sid
        let recording = UserDefaults.standard.bool(forKey: SessionRecorder.enabledKey)
        recordingStatus = recording ? .on : .off
        translator.configure(pair: pair)
        translator.apply = { [weak self] lineID, translated in
            guard let self, let idx = self.liveLines.firstIndex(where: { $0.id == lineID }) else { return }
            self.liveLines[idx].translation = translated
        }
        screen = .live
        sessionState = .preparing
        statusMessage = "마이크 권한·언어 모델 준비 중…"

        let engine = MicTranscriptionEngine()
        self.engine = engine
        // 대면 대화=마이크 1스트림 / 온라인 미팅=주 엔진이 시스템 소리(마이크는 아래 병행 엔진이 따로 남긴다).
        if recording { engine.recorder = makeRecorder(sessionID: sid, stream: mode == .onlineMeeting ? .system : .mic) }
        engine.onVolatile = { [weak self] text in Task { @MainActor in self?.applyVolatile(text) } }
        engine.onFinal    = { [weak self] text, cont in Task { @MainActor in self?.applyFinal(text, continuation: cont) } }
        engine.onLevel    = { [weak self] lv   in Task { @MainActor in self?.applyLevel(lv) } }
        engine.onStatus   = { [weak self] msg  in Task { @MainActor in
            self?.statusMessage = msg   // 준비·수신·중단 상태를 항상 표시 (침묵 실패 금지 — 안전②)
        } }
        engine.onRecognitionRestart = { [weak self] in Task { @MainActor in
            self?.commitStaleVolatile()   // 인식기 교체 직전, 떠 있던 잠정 자막을 확정으로 살림
        } }
        SpeechOut.onSpeakingChanged = { [weak self] speaking in Task { @MainActor in
            guard let self else { return }
            self.ttsSpeaking = speaking
            self.engine?.micMuted = speaking   // 읽어주기 재생 중 마이크 차단 (§1-⑧ — 대면 주 엔진)
            self.syncMicMute()                 // 온라인 미팅 마이크 엔진 = TTS ∪ 토글 합성 (§12)
        } }
        engine.onSpeakerSegments = { [weak self] segs in Task { @MainActor in
            self?.applySpeakerSegments(segs)
        } }
        speakerSegments.removeAll(); tentativeSegments.removeAll()
        speakerMap.removeAll(); nextRemoteNumber = 1
        mySpeakerIndex = nil; hiddenSpeakerIndexes.removeAll()
        lastFinalClock = 0
        popoutManuallyClosed = false; popoutUserMoved = false   // 새 세션 = 팝아웃 자동 표시 억제 해제(decisions §8)

        // 엔진 라우팅(decisions §2): 인니 포함 세션=WhisperKit(단일 인니=고정, 쌍=발화별 자동 감지) / 그 외=Apple.
        // 한⇄영 쌍은 당분간 Apple(언어1 기준) — 상대 영어 발화 인식은 Whisper 상향 시 개선(스파이크 한계 명시).
        let usesWhisper = (pair.a == .indo || pair.b == .indo)
        sessionUsesWhisper = usesWhisper   // 세션 메타(engineLabel·modelUsed)용

        // 온라인 미팅 = 마이크 엔진 병행 (decisions §12 · Route A) — 내 발화를 '나' 스트림으로 자막·녹취.
        // 실패해도 세션은 계속(소프트 — 시스템만 + 배너). 디아라이저 없음(마이크=나 고정), Whisper는 공유 파이프.
        if mode == .onlineMeeting {
            streamStates[.myMic] = StreamState()
            let mic = MicTranscriptionEngine()
            micEngine = mic
            if recording { mic.recorder = makeRecorder(sessionID: sid, stream: .mic) }
            mic.onVolatile = { [weak self] text in Task { @MainActor in self?.applyVolatile(text, stream: .myMic) } }
            mic.onFinal    = { [weak self] text, cont in Task { @MainActor in self?.applyFinal(text, continuation: cont, stream: .myMic) } }
            mic.onLevel    = { [weak self] lv   in Task { @MainActor in self?.applyMicLevel(lv) } }
            // onStatus 미배선 — 상태줄은 주(시스템) 엔진 소유, 마이크는 배너로만 (상태줄 충돌 방지)
            let micPair = pair
            Task { [weak self] in
                do {
                    try await mic.start(source: .mic, localeIdentifier: micPair.a.sttLocale,
                                        recognizer: usesWhisper ? .whisper : .apple,
                                        whisperLanguages: micPair.isSingle ? [micPair.a.code]
                                                                           : [micPair.a.code, micPair.b.code],
                                        diarization: false,
                                        // 이 스트림의 확정은 화자 분리 없이 무조건 '나'다(아래 applyFinal).
                                        // 감도를 대면 대화처럼 올리면 2m 밖 가족·동료 말소리가 '나' 자막이 되고,
                                        // 청각 당사자는 그 오라벨을 귀로 교차검증할 수 없다 → 근접 발화만 받는다.
                                        // ⚠️ Whisper 경로(인니 포함 쌍)에만 걸린다 — Apple 경로는 게이트가 없어
                                        // 한 단일·한↔영 온라인 미팅에서는 여전히 타인 발화가 '나'가 될 수 있다(별도 에픽).
                                        nearFieldOnly: true)
                    guard let self else { return }
                    self.syncMicMute()
                    #if os(macOS)
                    self.speakerOutputActive = OutputRoute.isBuiltInSpeaker   // 첫 판정 즉시(이후 티커 5초 주기)
                    #endif
                } catch {
                    guard let self else { return }
                    self.micEngine = nil
                    if case MicTranscriptionEngine.EngineError.micDenied = error {
                        self.micBannerText = "마이크 권한이 없어 상대 소리만 자막 중 — 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 VisualVoice를 켜면 내 발화도 담깁니다."
                    } else {
                        self.micBannerText = "내 마이크를 시작하지 못해 상대 소리만 자막 중 — \(error.localizedDescription)"
                    }
                    self.sessionNotes.append("내 마이크 시작 실패 — 상대 소리만 기록됨 (\(error.localizedDescription))")
                    NSLog("VV mic-dual: 마이크 엔진 소프트 실패 — %@", error.localizedDescription)
                }
            }
        }

        Task {
            do {
                try await engine.start(source: source, localeIdentifier: pair.a.sttLocale,
                                       recognizer: usesWhisper ? .whisper : .apple,
                                       whisperLanguages: pair.isSingle ? [pair.a.code]
                                                                       : [pair.a.code, pair.b.code])
                sessionState = .recording
                accumulated = 0
                resumedAt = Date()
                lastVoiceAt = Date()
                startTicker()
            } catch {
                sessionState = .idle
                statusMessage = "시작 실패 — \(error.localizedDescription)"
                self.engine = nil
                let mic = self.micEngine          // 주 엔진 실패 = 세션 불성립 — 마이크 엔진도 정리(리소스 누수 금지)
                self.micEngine = nil
                Task { await mic?.stop() }
            }
        }
    }

    func togglePause() {
        switch sessionState {
        case .recording:
            engine?.pause()
            micEngine?.pause()
            if let r = resumedAt { accumulated += Date().timeIntervalSince(r) }
            resumedAt = nil
            sessionState = .paused
        case .paused:
            do {
                try engine?.resume()
                try? micEngine?.resume()   // 마이크 스트림은 소프트(주 자막은 계속) — 실패 시 워치독이 복구
                resumedAt = Date()
                lastVoiceAt = Date()
                sessionState = .recording
            } catch {
                statusMessage = "재개 실패 — \(error.localizedDescription)"
            }
        default: break
        }
    }

    /// 정지(확인 다이얼로그 통과 후) — 세션 저장 → 세션 상세로 전환.
    /// `(정지확인방식)` = 확인 다이얼로그(잠정), `(종료후재개유예분)` 이어붙임은 후속.
    /// 무음 재시작·정지 시 잠정 자막을 확정으로 승격 — 마지막 발화 유실 방지 (0구간 버그 수정)
    private func commitStaleVolatile() {
        for stream in Array(streamStates.keys) {
            if let id = streamStates[stream]?.volatileID,
               let idx = liveLines.firstIndex(where: { $0.id == id }) {
                liveLines[idx].isVolatile = false
                if stream == .main { stampAndAssignSpeaker(at: idx) }
                else { liveLines[idx].speaker = .me }   // 마이크 스트림 = 나 고정 (§12)
            }
            streamStates[stream]?.volatileID = nil
        }
    }

    func stopSession() {
        guard sessionState == .recording || sessionState == .paused else { return }
        commitStaleVolatile()   // 마지막 잠정 발화도 세션에 저장
        if let r = resumedAt { accumulated += Date().timeIntervalSince(r) }
        ticker?.invalidate(); ticker = nil
        let stopping = engine
        engine = nil
        let stoppingMic = micEngine               // 온라인 미팅 마이크 엔진 동반 정리 (§12)
        micEngine = nil
        dualCaptureSession = false
        micBannerText = nil
        speakerOutputActive = false
        let finals = liveLines.filter { !$0.isVolatile }

        // 녹음 마감(WAV 헤더 확정)은 엔진 stop()이 한다. 자막이 한 줄도 없어 세션이 폐기되더라도
        // **녹음은 지우지 않는다** — 그 무자막 세션이 §13 증상의 유일한 증거이기 때문(SessionRecorder 주석 참조).
        let recordingID = pendingSessionID
        pendingSessionID = nil
        let hadRecording = recordingStatus == .on   // .failed면 파일이 온전하다고 말할 수 없다
        recordingStatus = .off
        Task { await stopping?.stop(); await stoppingMic?.stop() }

        // 대화(음성·타이핑)가 하나도 없으면 저장 없이 종료 — 빈 세션이 최근 기록에 남지 않게 (2026-07-17 제작자 지시)
        guard !finals.isEmpty else {
            sessionState = .idle
            statusMessage = nil
            metrics.reset()
            // 무고지 홈 복귀 금지(§3 정직 표기 · 2026-09-11) — 이 무자막 세션의 녹음이 §13 증상의 유일한 증거다.
            homeNotice = hadRecording
                ? "이번 세션에서는 말소리를 찾지 못했습니다 — 세션은 저장하지 않았지만 녹음은 남아 있어요 (설정 > 녹음 > Finder에서 보기)."
                : "이번 세션에서는 말소리를 찾지 못해 저장하지 않았습니다."
            screen = .home
            return
        }

        let startedAt = sessionStartedAt ?? Date()
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"
        // 세션 중 열화 사유 — 라이브 배너로만 알리던 것을 기록에 남긴다(§14 분석 루프가 조건을 알 수 있게).
        var notes = sessionNotes
        if audioKicks > 0 { notes.append("오디오 입력 끊김 자동 복구 \(audioKicks)회") }
        if translator.failedCount > 0 { notes.append("실시간 번역 실패 \(translator.failedCount)줄 — 그 줄은 번역 없이 기록됐어요") }
        if translator.droppedCount > 0 { notes.append("밀린 번역 \(translator.droppedCount)줄 건너뜀") }
        var session = Session(
            id: recordingID ?? UUID(),   // 녹음 파일 이름과 같은 ID — 삭제·조회가 이 한 값으로 이어진다
            title: "\(liveTitle) \(timeFmt.string(from: startedAt))",
            dateLabel: Session.dateLabel(for: startedAt), pairShort: pair.short,
            segments: finals.count, duration: LiveMetrics.format(accumulated),
            dotColor: Theme.rec,
            preview: finals.first?.source ?? "",
            transcript: finals,
            createdAt: startedAt,
            engineLabel: sessionUsesWhisper ? "WhisperKit" : "Apple SpeechTranscriber",
            modelUsed: sessionUsesWhisper ? MicTranscriptionEngine.whisperModelName : pair.a.sttLocale,
            notes: notes.isEmpty ? nil : notes)
        session.minutes = .generating
        sessions.insert(session, at: 0)

        sessionState = .idle
        statusMessage = nil
        metrics.reset()
        openDetail(session)

        // 회의록 생성 — 온디바이스, 완료 시 목록·열린 상세 화면에 반영 (실패도 사유 표기 — 침묵 실패 금지)
        // 이어서 AI 재번역 — 종료-후 잡 직렬화(회의록→재번역 순, 워게임 §D 동시실행·QoS: 메모리 동시 점유 방지)
        let sid = session.id
        let sessionPair = pair
        Task { [weak self] in
            let state = await MinutesGenerator.generate(from: finals)
            guard let self else { return }
            if let i = self.sessions.firstIndex(where: { $0.id == sid }) { self.sessions[i].minutes = state }
            if self.selectedSession?.id == sid { self.selectedSession?.minutes = state }
            self.startRetranslation(sid: sid, finals: finals, pair: sessionPair)
        }
    }

    // MARK: AI 재번역 (종료 후 · 앱 내장 MLX — decisions §11.4)

    var retransTask: Task<Void, Never>?                       // 취소 핸들(상세 취소 버튼)
    @Published var retransProgress: (done: Int, total: Int)?  // 'AI 재번역 중… n/N' — 영속 아님(라이브 신호)

    private func startRetranslation(sid: UUID, finals: [CaptionLine], pair: LanguagePair) {
        // 가드(워게임 §D 트리거_시점): 단일 언어 세션은 번역 자체가 없음 · 이중 실행 금지(.refining이 락)
        guard !pair.isSingle else { return }
        guard sessions.first(where: { $0.id == sid })?.refinement != .refining else { return }
        setRefinement(sid: sid, .refining)   // await 이전 동기 세팅 — 두 트리거가 같이 진입하는 창 차단

        retransTask = Task(priority: .utility) { [weak self] in   // 실시간 STT 보호 — 낮은 QoS(§D)
            // 새 녹음 진행 중이면 착수 보류(폴링 대기) — 첫 자막 <1.5초 성역 보호.
            // ponytail: 폴링 5초 — 일시정지/재개 스케줄러가 필요해지면 그때 승격.
            while let self, self.sessionState == .recording {
                try? await Task.sleep(for: .seconds(5))
            }
            guard let self else { return }
            let outcome = await ReTranslator.refine(lines: finals, pair: pair) { done, total in
                self.retransProgress = (done, total)
            }
            self.retransProgress = nil
            // write-back — sid 재조회(삭제 세션 부활 금지) + 줄단위 최소 병합(제목·참여인원 편집과 무충돌)
            guard let i = self.sessions.firstIndex(where: { $0.id == sid }) else { return }
            if !outcome.refined.isEmpty {
                var lines = self.sessions[i].transcript ?? []
                for j in lines.indices {
                    if let refined = outcome.refined[lines[j].id] { lines[j].refinedTranslation = refined }
                }
                self.sessions[i].transcript = lines
            }
            self.sessions[i].refinement = outcome.state
            if outcome.failed > 0 {   // 부분 실패 수치 영속(§3 정직 표기) — 화면의 N/M은 녹취록에서 파생(스키마 무변경)
                self.sessions[i].notes = (self.sessions[i].notes ?? [])
                    + ["AI 재번역 \(outcome.attempted)줄 중 \(outcome.failed)줄 실패 — 그 줄은 실시간 번역을 표시하고 있어요"]
            }
            if self.selectedSession?.id == sid {
                self.selectedSession?.transcript = self.sessions[i].transcript
                self.selectedSession?.refinement = outcome.state
                self.selectedSession?.notes = self.sessions[i].notes
            }
        }
    }

    /// 사용자 취소(상세 화면 버튼) — 이미 재번역된 줄은 유지(줄 마커가 정직 표기)
    func cancelRetranslation() { retransTask?.cancel() }

    private func setRefinement(sid: UUID, _ state: RefinementState) {
        if let i = sessions.firstIndex(where: { $0.id == sid }) { sessions[i].refinement = state }
        if selectedSession?.id == sid { selectedSession?.refinement = state }
    }

    // MARK: 전사 스트림 반영

    private func applyVolatile(_ raw: String, stream: CapStream = .main) {
        // 공백만 있는 잠정 결과 → 빈 "잠정" 박스 생성 버그 (2026-07-17 스크린샷 실측) — trim 후 판정
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        markFirstCaption()
        if statusMessage != nil { statusMessage = nil }   // 자막이 흐르기 시작하면 안내 배너 정리
        if let id = streamStates[stream]?.volatileID, let idx = liveLines.firstIndex(where: { $0.id == id }) {
            liveLines[idx].source = text
        } else {
            // 마이크 스트림 잠정 = '나' 칩 즉시 (화자 분리 없이 확정 신호 — §12)
            let line = CaptionLine(speaker: stream == .myMic ? .me : .unlabeled, source: text, translation: "",
                                   timecode: LiveMetrics.format(elapsedNow), isVolatile: true)
            streamStates[stream]?.volatileID = line.id
            // 동시 발화 시 잠정 순서 고정: 상대(main) 잠정 위 · 내 잠정 아래 (§12 화면 게이트 — 시각 위계)
            if stream == .main, let micVol = streamStates[.myMic]?.volatileID,
               let micIdx = liveLines.firstIndex(where: { $0.id == micVol }) {
                liveLines.insert(line, at: micIdx)
            } else {
                liveLines.append(line)
            }
        }
    }

    private func applyFinal(_ text: String, continuation: Bool = false, stream: CapStream = .main) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var st = streamStates[stream] ?? StreamState()
        defer { streamStates[stream] = st }
        // 잘못 쪼개진 문장 병합(2026-07-17 제작자 지시): "직전 확정이 6초 상한으로 발화 중간에서 잘렸을 때"만
        // 새 조각을 직전 줄에 붙이고 병합문 전체를 재번역. 판정 기준은 직전 확정의 절단 힌트 —
        // 현재 조각 기준으로 보던 초판 버그 수정(TTS 실측: 장문 3분할 미병합). 무음 종결은 부호 없어도 별개 문장.
        if !t.isEmpty, st.lastFinalContinuation, mergeIntoPreviousIfContinuation(t, stream: stream, state: st) {
            if let id = st.volatileID, let idx = liveLines.firstIndex(where: { $0.id == id }) {
                liveLines.remove(at: idx)   // 잠정 줄은 병합으로 소화
            }
            st.volatileID = nil
            st.lastFinalAt = Date()
            st.lastFinalContinuation = continuation
            return
        }
        if let id = st.volatileID, let idx = liveLines.firstIndex(where: { $0.id == id }) {
            if t.isEmpty {
                liveLines.remove(at: idx)
                st.lastFinalContinuation = false   // 무음·잡음 에피소드 — 직전 절단의 연속성 소멸
            } else {
                liveLines[idx].source = t
                liveLines[idx].isVolatile = false
                liveLines[idx].timecode = LiveMetrics.format(elapsedNow)
                if stream == .main { stampAndAssignSpeaker(at: idx) }
                else { liveLines[idx].speaker = .me }   // 마이크 확정 = 나 고정, 시계·분리기 미사용 (§12)
                translator.enqueue(lineID: id, text: t)   // 확정 즉시 상대 언어 번역 (쌍 세션)
                st.lastFinalAt = Date()
                st.lastFinalContinuation = continuation
                st.lastFinalLineID = id
            }
            st.volatileID = nil
        } else if !t.isEmpty {
            let line = CaptionLine(speaker: stream == .myMic ? .me : .unlabeled, source: t, translation: "",
                                   timecode: LiveMetrics.format(elapsedNow))
            liveLines.append(line)
            if stream == .main { stampAndAssignSpeaker(at: liveLines.count - 1) }
            translator.enqueue(lineID: line.id, text: t)
            st.lastFinalAt = Date()
            st.lastFinalContinuation = continuation
            st.lastFinalLineID = line.id
        } else {
            st.lastFinalContinuation = false
        }
    }

    /// 직전 확정 줄(상한 절단 힌트 확인 후 호출됨)에 t를 이어 붙이고 통째로 재번역. 성공 시 true.
    /// 오병합 방지: 7초 이내 연속 + 같은 언어 + 화자 동일(분리기 판정 시) + 280자 상한.
    /// 종결부호는 판정에 안 씀 — turbo가 절단부에 마침표를 지어냄("크리스마스입니다." — 2026-07-17 TTS 실측).
    /// 병합 대상 = "같은 스트림"의 직전 확정(lastFinalLineID) — 다른 스트림·타이핑 줄이 사이에 끼어도
    /// 자기 문장에만 붙는다(크로스 병합 차단, Blueprint §4). 끼임 시 문장이 위 줄에서 자라는 것은 의도된 표시.
    private func mergeIntoPreviousIfContinuation(_ t: String, stream: CapStream, state: StreamState) -> Bool {
        guard let target = state.lastFinalLineID,
              let idx = liveLines.firstIndex(where: { $0.id == target }),
              !liveLines[idx].isVolatile else { return false }
        let prev = liveLines[idx]
        guard !prev.isTyped,
              Date().timeIntervalSince(state.lastFinalAt) < 7.0,
              prev.source.count + t.count < 280 else { return false }
        // 언어가 갈리면 별도 문장 — 언어 경계 = 문장 경계 (TTS 실측: 인니어+한국어 과병합)
        if !pair.isSingle,
           TranslationCoordinator.detectLanguage(of: prev.source, between: pair)
               != TranslationCoordinator.detectLanguage(of: t, between: pair) { return false }
        if stream == .main {
            let endClock = engine?.audioClock ?? 0
            if let prevSpeaker = prev.fluidSpeaker,
               let newSpeaker = dominantSpeaker(from: lastFinalClock, to: endClock),
               prevSpeaker != newSpeaker { return false }   // 화자가 갈리면 별도 문장
            liveLines[idx].clockEnd = endClock   // 화자 backfill이 병합 구간까지 보도록 확장
            lastFinalClock = endClock
        }
        var merged = prev.source
        if merged.hasSuffix("…") { merged = String(merged.dropLast()) }
        else if merged.hasSuffix("...") { merged = String(merged.dropLast(3)) }
        merged = merged.trimmingCharacters(in: .whitespaces) + " " + t
        liveLines[idx].source = merged
        translator.enqueue(lineID: prev.id, text: merged)   // FIFO — 조각 번역을 병합 번역이 덮음
        return true
    }


    // MARK: 화자 분리 반영

    /// 확정 라인에 오디오 시계 범위를 찍고 지배 화자를 배정 (세그먼트가 늦으면 backfill이 재시도)
    private func stampAndAssignSpeaker(at index: Int) {
        let endClock = engine?.audioClock ?? 0
        let startClock = max(lastFinalClock, endClock - 15)
        liveLines[index].clockStart = startClock
        liveLines[index].clockEnd = endClock
        lastFinalClock = endClock
        assignSpeakerIfPossible(at: index)
    }

    private func assignSpeakerIfPossible(at index: Int) {
        guard liveLines.indices.contains(index),
              !liveLines[index].isTyped,               // 타이핑 발화는 항상 '나'
              !liveLines[index].speakerIsUserSet,      // 사용자 지정은 backfill이 덮지 않는다(QC 조건)
              let start = liveLines[index].clockStart,
              let end = liveLines[index].clockEnd,
              let idx = dominantSpeaker(from: start, to: end) else { return }
        liveLines[index].fluidSpeaker = idx
        liveLines[index].speaker = resolvedSpeaker(for: idx)
    }

    private func dominantSpeaker(from start: Double, to end: Double) -> Int? {
        var overlap: [Int: Double] = [:]
        for seg in speakerSegments + tentativeSegments where seg.end > start && seg.start < end {
            overlap[seg.speakerIndex, default: 0] += min(seg.end, end) - max(seg.start, start)
        }
        return overlap.max { $0.value < $1.value }?.key
    }

    private func resolvedSpeaker(for idx: Int) -> Speaker {
        if idx == mySpeakerIndex { return .me }
        if let mapped = speakerMap[idx] { return mapped }
        let assigned = Speaker.remote(nextRemoteNumber)
        nextRemoteNumber += 1
        speakerMap[idx] = assigned
        return assigned
    }

    private func applySpeakerSegments(_ segs: [MicTranscriptionEngine.SpeakerSegment]) {
        speakerSegments.append(contentsOf: segs.filter(\.finalized))
        tentativeSegments = segs.filter { !$0.finalized }
        if speakerSegments.count > 800 { speakerSegments.removeFirst(speakerSegments.count - 800) }
        // 화자 라벨이 자막보다 늦게 도착하는 경우 — 최근 미배정 라인 backfill (워게임 엣지케이스)
        for i in liveLines.indices.suffix(8)
        where !liveLines[i].isVolatile && liveLines[i].fluidSpeaker == nil {
            assignSpeakerIfPossible(at: i)
        }
    }

    /// 칩 팝오버: 이 화자를 '나'로 지정 (수동 지정 — 워게임 확정)
    func markSpeakerAsMe(_ idx: Int) {
        mySpeakerIndex = idx
        speakerMap[idx] = .me
        for i in liveLines.indices where liveLines[i].fluidSpeaker == idx {
            liveLines[i].speaker = .me
            liveLines[i].speakerIsUserSet = true
        }
    }

    /// 세션 상세 화자 재지정(2026-09-11 B②) — 저장된 세션의 줄 화자를 사용자가 바로잡는다.
    /// `wholeTrack`이면 같은 분리 트랙(fluidSpeaker)의 모든 줄, 아니면 이 줄만. 텍스트는 건드리지 않는다(§14 대조 기준 보존).
    /// selectedSession + sessions[] 이중 반영 → didSet 영속(renameParticipant와 동일 패턴).
    func reassignSpeaker(lineID: UUID, to speaker: Speaker, wholeTrack: Bool) {
        guard let sid = selectedSession?.id else { return }
        func apply(_ lines: inout [CaptionLine]) {
            guard let i = lines.firstIndex(where: { $0.id == lineID }) else { return }
            let track = lines[i].fluidSpeaker
            for j in lines.indices where j == i || (wholeTrack && track != nil && lines[j].fluidSpeaker == track) {
                lines[j].speaker = speaker
                lines[j].speakerIsUserSet = true
                lines[j].speakerUncertain = false
            }
        }
        if let si = sessions.firstIndex(where: { $0.id == sid }), var lines = sessions[si].transcript {
            apply(&lines); sessions[si].transcript = lines
        }
        if var s = selectedSession, s.id == sid, var lines = s.transcript {
            apply(&lines); s.transcript = lines; selectedSession = s
        }
    }

    // MARK: 종료 후 배치 작업 — 화자 다시 인식(B③) · 녹음 재전사(B④). 세션 진행 중 금지(공유 Whisper 파이프 경쟁 보호).

    @Published var batchProgress: (label: String, done: Int, total: Int)?   // 영속 아님 — 라이브 신호
    @Published var batchError: String?                                       // 실패 사유(상세 카드) — 다음 실행 시 소멸
    var canRunBatch: Bool { sessionState == .idle && batchProgress == nil }

    func recomputeSpeakers(sid: UUID, numSpeakers: Int?) {
        guard canRunBatch, let s = sessions.first(where: { $0.id == sid }) else { return }
        batchError = nil
        batchProgress = ("화자 다시 인식 중…", 0, 0)
        Task(priority: .utility) { [weak self] in
            defer { self?.batchProgress = nil }
            do {
                let (lines, o) = try await OfflineDiarizer.run(session: s, numSpeakers: numSpeakers) { d, t in
                    self?.batchProgress = ("화자 다시 인식 중…", d, t)
                }
                guard let self, let i = self.sessions.firstIndex(where: { $0.id == sid }) else { return }
                self.sessions[i].transcript = lines
                self.sessions[i].notes = (self.sessions[i].notes ?? []) + [o.summary]   // 결과를 수치로 남긴다(§3 정직 표기)
                if self.selectedSession?.id == sid {
                    self.selectedSession?.transcript = lines
                    self.selectedSession?.notes = self.sessions[i].notes
                }
            } catch {
                self?.batchError = error.localizedDescription
            }
        }
    }

    func retranscribe(sid: UUID) {
        guard canRunBatch, let s = sessions.first(where: { $0.id == sid }) else { return }
        batchError = nil
        batchProgress = ("재전사 준비 중…", 0, 0)
        // 온라인 미팅 세션 = 시스템 스트림 녹음이 있다 → 마이크 파일은 '나'(§12 규약). 대면은 마이크가 모두라 화자 미상.
        let hasSystem = SessionRecorder.items(for: sid).contains { $0.stream == .system }
        let sessionPair = pair
        Task(priority: .utility) { [weak self] in
            defer { self?.batchProgress = nil }
            do {
                let o = try await RecordingTranscriber.run(session: s, pair: sessionPair, dual: hasSystem) { msg in
                    self?.batchProgress = (msg, 0, 0)
                }
                guard let self, let i = self.sessions.firstIndex(where: { $0.id == sid }) else { return }
                self.sessions[i].retranscript = o.lines
                self.sessions[i].retranscriptInfo = o.info
                if self.selectedSession?.id == sid {
                    self.selectedSession?.retranscript = o.lines
                    self.selectedSession?.retranscriptInfo = o.info
                }
            } catch {
                self?.batchError = error.localizedDescription
            }
        }
    }

    /// 회의록 다시 만들기(2026-09-11 B⑥) — 실패·미가용 세션의 유일한 재시도 경로. 참여자 이름 정정분은 보존.
    /// 재번역이 도는 중엔 호출부가 막는다(Gemma+FM 동시 상주 금지 — 워게임 §D). 세션 진행 중이어도 무관(FM만 사용).
    func regenerateMinutes(sid: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == sid }),
              sessions[i].minutes != .generating, sessions[i].refinement != .refining,
              let finals = sessions[i].transcript, !finals.isEmpty else { return }
        // 사용자가 정정한 참여자 이름(hasKnownName)을 화자 라벨 기준으로 되살린다(Tester 조건)
        var keep: [String: String] = [:]
        if case .ready(let old) = sessions[i].minutes {
            for p in old.participants where p.hasKnownName { keep[p.speakerLabel] = p.name }
        }
        sessions[i].minutes = .generating
        if selectedSession?.id == sid { selectedSession?.minutes = .generating }
        Task { [weak self] in
            var state = await MinutesGenerator.generate(from: finals)
            if case .ready(var m) = state {
                for j in m.participants.indices { if let n = keep[m.participants[j].speakerLabel] { m.participants[j].name = n } }
                state = .ready(m)
            }
            guard let self, let k = self.sessions.firstIndex(where: { $0.id == sid }) else { return }
            self.sessions[k].minutes = state
            if self.selectedSession?.id == sid { self.selectedSession?.minutes = state }
        }
    }

    /// 칩 팝오버: 화자 숨기기/해제 — 자막에서만 숨김, 녹취록 보존 (워게임 확정)
    func toggleHideSpeaker(_ idx: Int) {
        if hiddenSpeakerIndexes.contains(idx) { hiddenSpeakerIndexes.remove(idx) }
        else { hiddenSpeakerIndexes.insert(idx) }
    }

    private func applyLevel(_ rms: Float) {
        // 원시 RMS 기준(2026-07-17 실측 보정: 침묵 0.08~0.12 · 발화 피크 0.24~0.57) — 발화 피크에서 만렙
        let step = min(7, Int(min(1, rms * 3) * 7))
        if metrics.meterStep != step { metrics.meterStep = step }   // 칸 변화 시에만 재렌더
        if rms > 0.03 { lastVoiceAt = Date() }                      // 무음 경고 = "입력이 아예 없음" 감지(낮은 임계)
        // 첫 자막 지연의 기점은 '뚜렷한 발화 시작'(근접 발화 기준 0.17 + 1.5초 정적 후 재출발) —
        // ⚠️ 2026-07-25: 엔진 게이트가 VAD로 옮겨가 이 임계와 더는 같지 않다(decisions §13). 원거리 발화는
        // 0.17을 못 넘으므로 앞사람만 말한 세션에서는 '첫 자막 +N초' 배지가 뜨지 않는다(계기판 공백, 자막은 정상).
        // 임계를 낮추면 소음이 시계를 출발시켜 수치가 부풀던 구 버그가 재발하므로, 엔진 발화 신호를 콜백으로
        // 받도록 바꾸기 전까지는 공백을 택한다 — 틀린 수치보다 없는 수치가 낫다.
        // 주변 소음이 녹음 시작 즉시 시계를 출발시켜 지연이 부풀던 문제 수정 (2026-07-17 실측 +44.8초 허수 원인)
        if rms > 0.17, sessionState == .recording {
            let now = Date()
            if metrics.firstCaptionDelay == nil,
               firstVoiceAt == nil || now.timeIntervalSince(lastLoudAt) > 1.5 {
                firstVoiceAt = now
            }
            lastLoudAt = now
        }
    }

    /// 실측: 첫 발화 감지 → 첫 자막 표출 지연 기록 (합격=체감 판단의 근거 수치)
    private func markFirstCaption() {
        guard metrics.firstCaptionDelay == nil, let fv = firstVoiceAt else { return }
        metrics.firstCaptionDelay = Date().timeIntervalSince(fv)
    }

    // ── 온라인 미팅 마이크 스트림 (decisions §12) ──

    /// 마이크 스트림 레벨 — 미터 2계통의 마이크 칸. 무음 경고는 양쪽 합집합(한쪽만 살아도 경고 없음).
    private func applyMicLevel(_ rms: Float) {
        let step = min(7, Int(min(1, rms * 3) * 7))
        if metrics.micMeterStep != step { metrics.micMeterStep = step }
        if rms > 0.03 { lastVoiceAt = Date() }
    }

    /// 마이크 엔진 음소거 = 읽어주기(TTS) 재생 ∪ "내 마이크" 토글 꺼짐 — 어느 쪽이든 차단.
    private func syncMicMute() {
        micEngine?.micMuted = ttsSpeaking || !micCaptureOn
    }

    /// "내 마이크" 토글 (라이브 상태바 — §12 화면 게이트). 끄면 떠 있던 내 잠정 줄은 폐기(미확정).
    func toggleMicCapture() {
        micCaptureOn.toggle()
        syncMicMute()
        if !micCaptureOn {
            // 이미 엔진 창에 쌓인 오디오도 함께 폐기 — 음소거는 탭 입력만 끊어서, 잔여 창이 1~2초 뒤
            // 전사되면 '마이크 꺼짐' 표시 상태에서 '나' 자막이 새로 뜬다(민감한 대화 직전에 끄는 용도).
            micEngine?.discardPendingAudio()
            if let id = streamStates[.myMic]?.volatileID,
               let idx = liveLines.firstIndex(where: { $0.id == id }) {
                liveLines.remove(at: idx)
            }
            streamStates[.myMic]?.volatileID = nil
            metrics.micMeterStep = 0   // 미터 정직화 — 꺼짐 상태에서 잔상 금지
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.sessionState == .recording else { return }
                self.metrics.elapsed = self.elapsedNow
                self.metrics.silenceSeconds = Int(Date().timeIntervalSince(self.lastVoiceAt))
                // 워치독 — 녹음 중인데 오디오 버퍼가 3초+ 끊기면 감지·자동 복구 (2026-07-17 "이어지지 않음" 실측 대응)
                if let engine = self.engine, engine.secondsSinceLastBuffer > 3 {
                    if !self.audioBroken { self.audioBroken = true; self.audioKicks += 1 }   // 끊김 에피소드 1회로 계수(notes)
                    self.statusMessage = "오디오 입력이 끊겼습니다 — 자동 복구 중… (\(Int(engine.secondsSinceLastBuffer))초)"
                    engine.kickAudio()
                } else {
                    self.audioBroken = false
                }
                // 마이크 스트림 워치독 — 상태줄 침범 없이 조용 복구(가시성은 마이크 미터가 담당 — §12).
                // 음소거 중(토글 꺼짐·TTS 재생)엔 버퍼가 원래 멎으므로 제외(헛 kick 방지).
                if let mic = self.micEngine, self.micCaptureOn, !self.ttsSpeaking,
                   mic.secondsSinceLastBuffer > 3 {
                    NSLog("VV mic-dual: 마이크 버퍼 %.0f초 끊김 — kickAudio", mic.secondsSinceLastBuffer)
                    mic.kickAudio()
                }
                // 스피커 출력 감시(5초 주기) — 이중 자막 경고 배너 (§12 (이중자막_방어_v1))
                self.tickCount += 1
                #if os(macOS)
                if self.micEngine != nil, self.tickCount % 10 == 0 {
                    let onSpeaker = OutputRoute.isBuiltInSpeaker
                    if self.speakerOutputActive != onSpeaker { self.speakerOutputActive = onSpeaker }
                }
                #endif
            }
        }
    }



    /// 끝난 세션 클릭 → 세션 상세(녹취록·회의록) — 라이브가 아니라.
    @Published var detailReturn: Screen = .home   // 상세에서 '뒤로' 시 복귀 화면(홈/보관함)

    func openDetail(_ session: Session) {
        if screen != .detail { detailReturn = screen == .archive ? .archive : .home }
        selectedSession = session
        screen = .detail
    }

    /// 세션 제목 변경 — 사이드바·보관함·상세 어디서나 반영, sessions.json 즉시 영속(didSet).
    func renameSession(_ id: UUID, to newTitle: String) {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }   // 빈 이름은 기존 유지
        if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].title = t }
        if selectedSession?.id == id { selectedSession?.title = t }
    }

    /// 회의록 참여 인원 이름 정정 — 회의록의 해당 화자 이름만 덮어쓰고 즉시 영속(2026-07-18).
    /// selectedSession(열린 상세) + sessions[](저장·목록) 이중 반영 → didSet 저장. 빈 이름은 무시.
    func renameParticipant(speakerLabel: String, to newName: String) {
        guard let sid = selectedSession?.id else { return }
        let t = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        func apply(_ minutes: inout MinutesState) {
            guard case .ready(var m) = minutes,
                  let i = m.participants.firstIndex(where: { $0.speakerLabel == speakerLabel }) else { return }
            m.participants[i].name = t
            minutes = .ready(m)
        }
        if let si = sessions.firstIndex(where: { $0.id == sid }) { apply(&sessions[si].minutes) }
        if var s = selectedSession, s.id == sid { apply(&s.minutes); selectedSession = s }
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        SessionRecorder.deleteRecordings(for: session.id)   // 제작자 지시 2026-07-30: 세션과 녹음은 함께 사라진다
        if selectedSession?.id == session.id {
            selectedSession = nil
            screen = .home
        }
    }

    /// 삭제 확인 다이얼로그 문구 — 네 진입점(기록 보관함·사이드바·홈·세션 상세)이 공유한다(규칙 4).
    /// 사라지는 것을 수량·용량까지 밝힌다: 조용히 없어지는 데이터가 없어야 하고(§3),
    /// 1GB짜리 분석 자료를 실수로 날리는 일도 막는다(목업 컨펌 2026-07-30).
    func deleteWarning(for session: Session?) -> String {
        let base = "녹취록과 회의록이 함께 삭제됩니다. 되돌릴 수 없습니다."
        guard let session else { return base }
        let (count, bytes) = SessionRecorder.summary(for: session.id)
        guard count > 0 else { return base }
        return "녹취록·회의록과 녹음 파일 \(count)개(\(SessionRecorder.sizeLabel(bytes)))가 함께 삭제됩니다. 되돌릴 수 없습니다."
    }

    private func makeRecorder(sessionID: UUID, stream: SessionRecorder.Stream) -> SessionRecorder {
        SessionRecorder(sessionID: sessionID, stream: stream) { [weak self] reason in
            Task { @MainActor in
                self?.recordingStatus = .failed(reason)   // 실패는 화면으로 — 침묵 실패 금지
                self?.sessionNotes.append("녹음 저장 중단 — \(reason)")
            }
        }
    }

    /// 타이핑 발화 — 대화 흐름에 내 발화로 추가, 쌍 세션이면 상대 언어로 자동 번역 (§1-⑧ ⓐⓑ).
    func sendTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }   // QC: 빈 전송 차단
        let line = CaptionLine(speaker: .me, source: trimmed, translation: "",
                               timecode: LiveMetrics.format(elapsedNow), isTyped: true)
        liveLines.append(line)
        translator.enqueue(lineID: line.id, text: trimmed)
    }
}

/// 읽어주기(TTS) — 시스템 음성합성, 온디바이스·무의존.
/// 재생 중 마이크 차단(자기 소리 재자막 루프 방지 — §1-⑧) + 종료 후 0.3초 잔향 여운을 두고 해제.
enum SpeechOut {
    private static let synth = AVSpeechSynthesizer()
    private static let watcher = Watcher()
    /// 재생 상태 변화 통지 — CaptionModel이 엔진 마이크 차단(micMuted)에 배선
    static var onSpeakingChanged: ((Bool) -> Void)?

    static func say(_ text: String, langCode: String) {
        guard !text.isEmpty else { return }
        synth.delegate = watcher
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        onSpeakingChanged?(true)
        let utterance = AVSpeechUtterance(string: text)
        let voiceLang = ["ko": "ko-KR", "en": "en-US", "id": "id-ID"][langCode] ?? "ko-KR"
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLang)
        synth.speak(utterance)
    }

    private final class Watcher: NSObject, AVSpeechSynthesizerDelegate {
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { done() }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { done() }
        private func done() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {   // 스피커 잔향 여운 — 꼬리 재자막 차단
                guard !SpeechOut.synth.isSpeaking else { return }     // 연속 재생 중이면 차단 유지
                SpeechOut.onSpeakingChanged?(false)
            }
        }
    }
}

/// 패널 상시 컨트롤 상태 — decisions.md §6(밀도·글자 크기·번역·불투명도).
@MainActor
final class PanelSettings: ObservableObject {
    enum Density: String { case simple, detailed }   // 간결 / 상세 (raw = UserDefaults 영속화용)
    @Published var density: Density        { didSet { d.set(density.rawValue, forKey: K.density) } }
    @Published var fontScale: CGFloat      { didSet { d.set(Double(fontScale), forKey: K.fontScale) } }  // 하한 0.7 상한 1.8
    @Published var showTranslation: Bool   { didSet { d.set(showTranslation, forKey: K.showTranslation) } }
    @Published var opacity: Double         { didSet { d.set(opacity, forKey: K.opacity) } }             // 배경 딤 0.65~0.95
    @Published var autoShowPopout: Bool    { didSet { d.set(autoShowPopout, forKey: K.autoShowPopout) } } // 창 가림 자동 표시(decisions §8)
    @Published var recordAudio: Bool       { didSet { d.set(recordAudio, forKey: K.recordAudio) } }       // 세션 음원 저장(decisions §14)
    @Published var replaceRules: [ReplaceRule] = ReplaceRule.load() { didSet { ReplaceRule.save(replaceRules) } }   // 치환 규칙(B⑤)
    /// 무갭 발화 조기 확정(LocalAgreement · 실험 · 기본 OFF) — 엔진이 세션 시작 시 읽는다(C②)
    @Published var localAgreement: Bool = UserDefaults.standard.bool(forKey: MicTranscriptionEngine.localAgreementKey) {
        didSet { UserDefaults.standard.set(localAgreement, forKey: MicTranscriptionEngine.localAgreementKey) }
    }

    /// 표시용 치환 — 확정 줄·상세·내보내기가 이 한 함수를 지난다(규칙 4). 원문은 불변.
    func display(_ source: String) -> String { ReplaceRule.apply(source, rules: replaceRules) }

    // 설정 영속화 — UserDefaults (2026-07-18 `(설정영속화범위)` 확정, 설정 화면 배선). didSet은 init에선 미발화.
    private let d = UserDefaults.standard
    private enum K {
        static let density = "vv.density", fontScale = "vv.fontScale", showTranslation = "vv.showTranslation"
        static let opacity = "vv.opacity", autoShowPopout = "vv.autoShowPopout"
        static let recordAudio = SessionRecorder.enabledKey
    }
    init() {
        d.register(defaults: [K.density: "simple", K.fontScale: 1.0, K.showTranslation: true, K.opacity: 0.85,
                              K.autoShowPopout: true, K.recordAudio: true])
        density = Density(rawValue: d.string(forKey: K.density) ?? "simple") ?? .simple
        fontScale = CGFloat(d.double(forKey: K.fontScale))
        showTranslation = d.bool(forKey: K.showTranslation)
        opacity = d.double(forKey: K.opacity)
        autoShowPopout = d.bool(forKey: K.autoShowPopout)
        recordAudio = d.bool(forKey: K.recordAudio)
    }
}
