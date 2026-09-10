import SwiftUI
import AVFoundation

/// 온보딩 — 첫 실행만(hasOnboarded). 환영 → 권한 사전설명 → 언어팩 준비 → 시작 (decisions §5 · 목업 컨펌 2026-07-18).
/// 각 단계 건너뛰기 가능(온디맨드 폴백 있음). 언어팩=한/영 Speech + 인니 WhisperKit 선다운로드(번역팩은 첫 번역에서 자동).
struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @State private var step = 0
    enum PackStatus { case waiting, downloading, done }
    @State private var pack: [String: PackStatus] = ["ko": .waiting, "id": .waiting, "en": .waiting]

    var body: some View {
        ZStack {
            Theme.bgMain.ignoresSafeArea()
            VStack(spacing: 0) {
                dots.padding(.top, 24)
                Spacer()
                content
                Spacer()
            }
            .frame(maxWidth: 460)
            .padding(40)
        }
        .foregroundStyle(Theme.ink)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i == step ? Theme.accent : Theme.hair)
                    .frame(width: i == step ? 20 : 7, height: 7)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: permission
        default: languagePack
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            icon("message.fill")
            Text("VisualVoice").font(.system(size: 26, weight: .bold))
            Text("대화를 실시간 자막으로 보고, 번역·회의록까지.\n전 과정 온디바이스라 대화 내용은 기기 밖으로 나가지 않습니다.")
                .multilineTextAlignment(.center).font(.system(size: 14)).foregroundStyle(Theme.ink2).lineSpacing(4)
            primaryButton("시작하기") { step = 1 }
        }
    }

    private var permission: some View {
        VStack(spacing: 16) {
            icon("mic.fill")
            Text("권한 안내").font(.system(size: 22, weight: .bold))
            Text("마이크 — 대면 대화를 자막으로 바꾸는 데 필요합니다.\n화면 기록은 줌·팀즈 등 온라인 미팅 소리를 자막할 때만(그 기능 켤 때 요청).")
                .multilineTextAlignment(.center).font(.system(size: 13.5)).foregroundStyle(Theme.ink2).lineSpacing(4)
            primaryButton("마이크 허용") {
                Task { _ = await AVCaptureDevice.requestAccess(for: .audio); step = 2 }
            }
            ghostButton("나중에 (세션 시작 시 요청)") { step = 2 }
        }
    }

    private var languagePack: some View {
        VStack(spacing: 12) {
            icon("globe")
            Text("언어팩 준비").font(.system(size: 22, weight: .bold))
            Text("미리 받아두면 세션이 바로 시작됩니다.").font(.system(size: 13.5)).foregroundStyle(Theme.ink2)
            VStack(spacing: 8) {
                langRow("한국어", pack["ko"] ?? .waiting)
                langRow("인도네시아어", pack["id"] ?? .waiting)
                langRow("영어", pack["en"] ?? .waiting)
            }.padding(.top, 4)
            Text("번역팩은 첫 번역에서 자동으로 받습니다.").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            primaryButton("시작하기") { app.finishOnboarding() }
            ghostButton("건너뛰고 나중에 받기") { app.finishOnboarding() }
        }
        .task { await downloadPacks() }
    }

    /// 순차 선다운로드 — 완료 상태를 하나씩 갱신(건너뛰어도 온디맨드 폴백).
    private func downloadPacks() async {
        pack["ko"] = .downloading
        await MicTranscriptionEngine.preheatAssets(localeIdentifier: "ko_KR")
        pack["ko"] = .done
        pack["id"] = .downloading
        await MicTranscriptionEngine.preheatWhisper()
        pack["id"] = .done
        pack["en"] = .downloading
        await MicTranscriptionEngine.preheatAssets(localeIdentifier: "en_US")
        pack["en"] = .done
    }

    // ── 재사용 헬퍼 ──
    private func icon(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 26)).foregroundStyle(Theme.accent)
            .frame(width: 56, height: 56).background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 15))
    }
    private func primaryButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x062A30))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).padding(.top, 8)
    }
    private func ghostButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink3) }
            .buttonStyle(.plain)
    }
    private func langRow(_ name: String, _ st: PackStatus) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .semibold))
            Spacer()
            switch st {
            case .done:        Text("완료 ✓").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.good)
            case .downloading: Text("받는 중…").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.accent)
            case .waiting:     Text("대기").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hair))
    }
}
