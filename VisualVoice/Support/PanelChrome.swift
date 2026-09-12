import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    /// 0xRRGGBB 정수로 색을 만든다 (팔레트 색상 정의용).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#if os(macOS)  // 팝아웃·창 제어 3종(AppKit) — iPad 제외 범위. Color(hex:)는 공용이라 위에 둠.
/// 다크 반투명(HUD) 배경 — "영상 위 가독성" 규약.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 플로팅 항상-위 패널 창 설정.
/// 창 알파는 항상 1.0 — 불투명도 슬라이더는 배경 딤에만 적용(자막 텍스트는 절대 투명해지지 않음, 2026-07-17 치명 결함 수정).
/// 단순화: 완전 무테두리·둥근 모서리 커스텀 창은 후속 다듬기. 지금은 hiddenTitleBar + floating으로 충분.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }
    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = .floating                       // 항상 위
        window.isMovableByWindowBackground = true       // 배경 드래그로 이동
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0                        // 텍스트 가독 불변 조건
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)  // 전체화면 앱 위에도
    }
}

/// 창 생명주기 관찰자 — 특정 NSWindow의 가림/최소화(onOcclusion) 및 사용자 이동·크기변경(onModified)을 보고.
/// 팝아웃 자동 표시(창 가림 시) 배선에 쓰인다.
/// 주의: occlusionState는 '완전 가림'에만 반응(부분 가림 무반응) — 실측 확인 대상.
struct WindowEventObserver: NSViewRepresentable {
    var onOcclusion: ((Bool) -> Void)? = nil    // true = 가려짐/최소화(비가시)
    var onModified: (() -> Void)? = nil         // 사용자 이동·크기변경

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator {
        let parent: WindowEventObserver
        weak var window: NSWindow?
        var armAt = Date()   // 초기 프로그램 배치의 이동/리사이즈 이벤트 무시용

        init(_ p: WindowEventObserver) { parent = p }

        func attach(to w: NSWindow?) {
            guard let w, w !== window else { return }
            window = w
            armAt = Date().addingTimeInterval(0.7)
            let nc = NotificationCenter.default
            if parent.onOcclusion != nil {
                nc.addObserver(self, selector: #selector(recompute), name: NSWindow.didChangeOcclusionStateNotification, object: w)
                nc.addObserver(self, selector: #selector(recompute), name: NSWindow.didMiniaturizeNotification, object: w)
                nc.addObserver(self, selector: #selector(recompute), name: NSWindow.didDeminiaturizeNotification, object: w)
                recompute()
            }
            if parent.onModified != nil {
                nc.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: w)
                nc.addObserver(self, selector: #selector(moved), name: NSWindow.didResizeNotification, object: w)
            }
        }
        @objc private func recompute() {
            guard let w = window else { return }
            parent.onOcclusion?(w.isMiniaturized || !w.occlusionState.contains(.visible))
        }
        @objc private func moved() { if Date() > armAt { parent.onModified?() } }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

/// "Finder에서 보기" — 녹음 파일을 재전사 도구에 넣을 수 있도록 위치만 알려준다.
/// 인앱 재생기는 v1 범위 밖(녹음은 계측 목적 한정). 설정·세션 상세가 공유한다.
struct FinderRevealButton: View {
    var urls: [URL] = []                              // 비면 폴더 자체를 연다
    var folder: URL = SessionRecorder.folder

    var body: some View {
        Button {
            if urls.isEmpty {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        } label: {
            Text("Finder에서 보기")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hair))
        }.buttonStyle(.plain)
    }
}
#endif
