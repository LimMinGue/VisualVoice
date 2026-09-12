import AVFoundation
import Foundation

/// 세션 음원 녹음 — 원음(장치가 준 그대로) + 인식 음원(엔진이 실제로 소비한 신호)을 WAV로 남긴다.
///
/// 제품 기능이 아니라 **진단 계측**이다. 자막·번역이 틀렸을 때 "무엇이 들어왔고 엔진은 무엇을 들었나"를
/// 증거로 남겨, 합성 TTS에 의존하던 회귀 자산을 실사용 녹음으로 대체하는 것이 목적.
/// 두 계통을 함께 남기는 이유: 원음만으로는 변환 단계 고장을 못 잡고(2026-07-17 VP 롤백이 그 사례),
/// 인식 음원만으로는 마이크 자체 문제와 구분되지 않는다.
///
/// ⚠️ `write` 계열은 **오디오 렌더 스레드**에서 호출된다. 파일 I/O는 전용 직렬 큐로만 나간다 —
/// 여기서 디스크를 기다리면 버퍼가 드롭되고 그대로 자막 끊김이 된다.
final class SessionRecorder {
    enum Stream: String { case mic, system }
    enum Kind: String {
        case raw, asr
        /// 확정된 UI 용어 — 축약·의역 금지.
        var label: String { self == .raw ? "원음" : "인식 음원" }
    }

    // MARK: 트랙 (스트림 × 계통 하나 = 파일 하나)

    /// 모든 상태는 소유자의 직렬 큐에서만 만진다(락 불요).
    private final class Track {
        private let sessionID: UUID
        private let stream: Stream
        private let kind: Kind
        private var file: AVAudioFile?
        private var format: AVAudioFormat?
        private var part = 1
        var dead = false

        init(sessionID: UUID, stream: Stream, kind: Kind) {
            self.sessionID = sessionID; self.stream = stream; self.kind = kind
        }

        var label: String { "\(stream.rawValue)-\(kind.rawValue)" }

        func write(_ buffer: AVAudioPCMBuffer) throws {
            // 포맷 불일치 = 최초 1회이거나, 세션 도중 입력 장치가 바뀐 순간(에어팟 배터리 사망 등).
            // 그때 쓰기를 포기하면 남은 구간을 통째로 잃으므로 새 파일로 롤오버한다.
            if format != buffer.format {
                if format != nil { part += 1 }
                file = nil                       // 이전 파일 닫기(ARC) — 헤더가 여기서 확정된다
                file = try SessionRecorder.makeFile(sessionID: sessionID, stream: stream,
                                                    kind: kind, part: part, format: buffer.format)
                format = buffer.format
            }
            try file?.write(from: buffer)
        }

        func finish() { file = nil }
    }

    private let queue: DispatchQueue
    private let rawTrack: Track
    private let asrTrack: Track
    private let onFailure: (String) -> Void
    private var failureReported = false

    init(sessionID: UUID, stream: Stream, onFailure: @escaping (String) -> Void) {
        // 스트림당 큐 1개 — 원음·인식 음원이 같은 큐를 공유해 동시 쓰기가 2개를 넘지 않는다.
        queue = DispatchQueue(label: "visualvoice.record.\(stream.rawValue)", qos: .utility)
        rawTrack = Track(sessionID: sessionID, stream: stream, kind: .raw)
        asrTrack = Track(sessionID: sessionID, stream: stream, kind: .asr)
        self.onFailure = onFailure
    }

    /// 원음 — 탭 콜백이 끝나면 버퍼가 무효가 되므로 **복사가 필수**다.
    func write(raw buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        enqueue(copy, into: rawTrack)
    }

    /// 인식 음원 — `process()`가 매 호출 새로 할당한 버퍼라 복사 없이 그대로 넘긴다.
    func write(asr buffer: AVAudioPCMBuffer) { enqueue(buffer, into: asrTrack) }

    func finish() {
        queue.async { [rawTrack, asrTrack] in
            rawTrack.finish(); asrTrack.finish()
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, into track: Track) {
        queue.async { [weak self] in
            guard let self, !track.dead else { return }
            do {
                try track.write(buffer)
            } catch {
                track.dead = true
                NSLog("VV rec: 쓰기 실패(%@) — %@", track.label, error.localizedDescription)
                // 디스크 부족·권한 등 — 녹음만 멈추고 자막은 계속(소프트 실패, 침묵 실패 금지).
                guard !self.failureReported else { return }
                self.failureReported = true
                self.onFailure(error.localizedDescription)
            }
        }
    }

    /// 포맷 무관 깊은 복사 — 채널 레이아웃을 그대로 두고 바이트만 옮긴다.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }
        out.frameLength = buffer.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        for i in 0..<min(src.count, dst.count) {
            guard let s = src[i].mData, let d = dst[i].mData else { continue }
            memcpy(d, s, Int(min(src[i].mDataByteSize, dst[i].mDataByteSize)))
        }
        return out
    }

    private static func makeFile(sessionID: UUID, stream: Stream, kind: Kind,
                                 part: Int, format: AVAudioFormat) throws -> AVAudioFile {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = part > 1 ? "-\(part)" : ""
        let url = folder.appendingPathComponent(
            "\(sessionID.uuidString)-\(stream.rawValue)-\(kind.rawValue)\(suffix).wav")
        // 16비트 정수 WAV — 재전사 도구가 가장 무난히 먹는 형식이고, 잘려도 잘린 데까지 읽힌다
        // (M4A는 파일을 정상적으로 닫아야 색인이 기록돼, 크래시 세션의 증거가 통째로 날아간다).
        // Float32로 쓰면 용량만 2배이고 음성 진단에서 얻는 것이 없다.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        return try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
}

// MARK: - 파일 관리 (세션 수명과 묶인 정리·조회)

extension SessionRecorder {
    /// 녹음 켜짐 설정의 단일 출처. 설정 화면(PanelSettings)과 세션 로직(AppModel)이 같은 키를 본다 —
    /// 여기 두는 이유는 화면 계층(@MainActor) 밖이라 어느 쪽에서 읽어도 격리 경고가 없기 때문.
    static let enabledKey = "vv.recordAudio"

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisualVoice", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    struct Item: Identifiable {
        let url: URL
        let kind: Kind
        let stream: Stream
        let bytes: Int64
        var id: URL { url }
        var sizeLabel: String { SessionRecorder.sizeLabel(bytes) }
    }

    static func items(for sessionID: UUID) -> [Item] {
        let prefix = sessionID.uuidString
        return allFiles().compactMap { url -> Item? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { return nil }
            let parts = name.dropFirst(prefix.count).split(separator: "-")
            guard parts.count >= 2,
                  let stream = Stream(rawValue: String(parts[0])),
                  let kind = Kind(rawValue: String(parts[1])) else { return nil }
            return Item(url: url, kind: kind, stream: stream, bytes: size(of: url))
        }
        // 표시 순서 — 시스템 먼저, 각 스트림 안에서 원음 먼저.
        .sorted { ($0.stream == .system ? 0 : 1, $0.kind == .raw ? 0 : 1, $0.url.lastPathComponent)
                < ($1.stream == .system ? 0 : 1, $1.kind == .raw ? 0 : 1, $1.url.lastPathComponent) }
    }

    /// 구 세션 날짜 복구 재료 — createdAt이 없는 세션의 진짜 시작 시각은 녹음 WAV 생성 시각뿐이다(2026-09-11).
    static func earliestFileDate(for sessionID: UUID) -> Date? {
        items(for: sessionID)
            .compactMap { try? $0.url.resourceValues(forKeys: [.creationDateKey]).creationDate }
            .min()
    }

    /// 삭제 다이얼로그·상세 화면용 요약. 파일이 없으면 (0, 0) — 호출부가 UI 자체를 숨긴다.
    static func summary(for sessionID: UUID) -> (count: Int, bytes: Int64) {
        let items = items(for: sessionID)
        return (items.count, items.reduce(0) { $0 + $1.bytes })
    }

    static func deleteRecordings(for sessionID: UUID) {
        for item in items(for: sessionID) { try? FileManager.default.removeItem(at: item.url) }
    }

    static func totalBytes() -> Int64 { allFiles().reduce(0) { $0 + size(of: $1) } }

    // 녹음을 지우는 경로는 **사용자가 세션을 삭제할 때 하나뿐**이다(`AppModel.delete`).
    //
    // 초기 설계는 "빈 세션 폐기 시 동반 삭제"와 "고아 파일 자동 청소"를 계획했으나 **철회했다**
    // (2026-07-30). 두 가지 이유:
    //   ① 보관 정책이 "무제한·자동 삭제 없음"이라 자동 삭제 자체가 그 결정과 어긋난다.
    //   ② 결정적으로, **자막이 한 줄도 안 나온 세션은 빈 세션으로 폐기**되는데(2026-07-17 규칙),
    //      그 세션이야말로 쫓고 있는 증상("앞사람 말이 통째로 사라진다")의 유일한 증거다.
    //      동반 삭제는 가장 분석하고 싶은 녹음을 앱이 먼저 지우는 결과가 된다.
    // 대가: 세션에 붙지 않은 녹음이 남는다(폐기된 빈 세션·크래시). 설정의 총 사용량에 잡히고
    // Finder에서 관리할 수 있으므로 보이지 않는 누수는 아니다.

    /// 크래시·강제 종료로 마감되지 않은 WAV 복구.
    ///
    /// 실측(2026-07-30): 파일을 닫지 못하면 **오디오 데이터는
    /// 전부 디스크에 남지만** RIFF·data 청크의 크기 필드가 0이라 재생기·재전사 도구가 '0프레임'으로
    /// 읽는다. 두 필드를 실제 길이로 고쳐 쓰면 그대로 살아난다(실측: 80,000프레임 정확히 복구).
    /// 하필 크래시한 세션이 가장 분석하고 싶은 세션이므로('전사 행'이 강제 종료를 유발한다) 자동으로 한다.
    ///
    /// ⚠️ 고아 청소와 같은 이유로 **앱 시작 시에만** 부른다 — 진행 중인 세션의 열린 파일을 건드리면 안 된다.
    static func repairInterrupted() {
        for url in allFiles() { repairHeader(url) }
    }

    /// 헤더 앞부분만 읽고 4바이트 필드 2개만 되쓴다 — 수백 MB 파일을 메모리에 올리지 않는다.
    private static func repairHeader(_ url: URL) {
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        guard let total = try? handle.seekToEnd(), total > 44 else { return }
        try? handle.seek(toOffset: 0)
        guard let head = try? handle.read(upToCount: 8192), head.count >= 12 else { return }

        var offset = 12
        while offset + 8 <= head.count {
            let id = String(bytes: head[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self) }
            guard id == "data" else {
                offset += 8 + Int(size) + Int(size) % 2
                continue
            }
            let payload = total - UInt64(offset + 8)
            // 정상 종료된 파일은 크기 필드가 이미 맞다 — 손대지 않는다.
            guard size == 0, payload > 0, payload < UInt64(UInt32.max) else { return }
            try? handle.seek(toOffset: UInt64(offset + 4))
            try? handle.write(contentsOf: withUnsafeBytes(of: UInt32(payload).littleEndian) { Data($0) })
            try? handle.seek(toOffset: 4)
            try? handle.write(contentsOf: withUnsafeBytes(of: UInt32(total - 8).littleEndian) { Data($0) })
            NSLog("VV rec: 중단된 녹음 헤더 복구 — %@ (%llu바이트)", url.lastPathComponent, payload)
            return
        }
    }

    static func sizeLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func allFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]))?
            .filter { $0.pathExtension == "wav" } ?? []
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
