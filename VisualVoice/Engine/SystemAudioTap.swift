#if os(macOS)  // 시스템 오디오 캡처(SCK) — iPad 제외 범위 (decisions §10)
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import CoreAudio

/// 시스템(다른 앱) 오디오 캡처 — ScreenCaptureKit 경로 (decisions §2: 미팅 캡처 기본, 실측 검증 대상).
/// 영상 프레임은 받아서 즉시 버림(오디오 전용 등록 시 스트림이 조용히 멈추는 사례 대응). 자기 프로세스 오디오 제외.
final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private let onEvent: (String) -> Void          // 상태·오류를 화면에 그대로 보고 (침묵 실패 금지)
    private let audioQueue = DispatchQueue(label: "visualvoice.systemaudio")
    private let videoQueue = DispatchQueue(label: "visualvoice.systemvideo")
    private var receivedFirstAudio = false

    enum TapError: LocalizedError {
        case permissionDenied, noDisplay
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "화면 기록 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 VisualVoice를 켠 뒤, 앱을 다시 실행해 주세요."
            case .noDisplay:
                return "캡처할 디스플레이를 찾지 못했습니다."
            }
        }
    }

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
         onEvent: @escaping (String) -> Void = { _ in }) {
        self.onBuffer = onBuffer
        self.onEvent = onEvent
    }

    func start() async throws {
        // 0) 권한 사전 점검 — 없으면 시스템 요청 팝업을 띄우고 명확히 실패 (조용한 무자막 금지)
        if !CGPreflightScreenCaptureAccess() {
            NSLog("VV SystemAudioTap: 화면 기록 권한 없음 — 요청 팝업 표시")
            CGRequestScreenCaptureAccess()   // 설정 앱 유도 팝업 (승인 후 앱 재실행 필요)
            throw TapError.permissionDenied
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw TapError.noDisplay }
        NSLog("VV SystemAudioTap: 디스플레이 확보 %dx%d", display.width, display.height)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true          // 자기 소리(읽어주기 TTS 등) 제외
        config.width = 64
        config.height = 64
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)   // 0.5fps — 오디오만 목적

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)  // 받고 버림
        try await stream.startCapture()
        self.stream = stream
        NSLog("VV SystemAudioTap: 캡처 시작됨")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }               // 영상 프레임은 버림
        guard let pcm = sampleBuffer.asPCMBuffer else { return }
        if !receivedFirstAudio {
            receivedFirstAudio = true
            NSLog("VV SystemAudioTap: 첫 오디오 버퍼 수신 (%.0fHz %dch)", pcm.format.sampleRate, pcm.format.channelCount)
            onEvent("시스템 오디오 수신 중")
        }
        onBuffer(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("VV SystemAudioTap: 스트림 중단 — %@", error.localizedDescription)
        onEvent("시스템 오디오 캡처가 중단되었습니다 — \(error.localizedDescription)")
    }
}

/// 기본 출력이 '내장 스피커'인지 — 이중 자막 경고 배너 판정 (decisions §12 `(이중자막_방어_v1)`).
/// 에어팟(블루투스)·외장 장치는 false. 내장 3.5mm 헤드폰은 transport가 같아 dataSource('ispk')로 구분.
/// 조회 실패 시 false — 거짓 경고 금지(확실할 때만 배너).
enum OutputRoute {
    static var isBuiltInSpeaker: Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return false }

        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBuiltIn else { return false }

        var source = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDataSource
        addr.mScope = kAudioObjectPropertyScopeOutput
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &source) == noErr else {
            return true   // 내장 transport인데 dataSource 미제공 = 스피커 단일 구성으로 간주
        }
        return source == 0x6973_706B   // 'ispk' — 내장 스피커 ('hdpn'=내장 헤드폰 잭)
    }
}

extension CMSampleBuffer {
    /// CMSampleBuffer(오디오) → AVAudioPCMBuffer (SCK 오디오 콜백 → 전사 파이프라인 연결용)
    var asPCMBuffer: AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(self) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
#endif
