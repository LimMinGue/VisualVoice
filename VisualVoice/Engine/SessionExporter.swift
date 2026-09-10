#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

/// 내보내기 형식 — DOCX는 경량 store-ZIP/OOXML로 무의존 생성(decisions §30 · 2026-07-18).
enum ExportFormat: String, CaseIterable {
    case txt = "TXT", md = "Markdown", pdf = "PDF", docx = "DOCX", json = "JSON"   // JSON = §14 분석 루프용 기계 판독(2026-09-11 B⑦)
    var ready: Bool { true }
    var fileExtension: String {
        switch self { case .txt: "txt"; case .md: "md"; case .pdf: "pdf"; case .docx: "docx"; case .json: "json" }
    }
    var utType: UTType {
        switch self {
        case .txt: .plainText
        case .md: UTType(filenameExtension: "md") ?? .plainText
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .json: .json
        }
    }
}

struct ExportOptions {
    var includeTimecode = true
    var includeSpeaker = true
    var includeTranslation = true
    var includeMinutes = true
    var useRefined = true       // 번역 = AI 재번역 우선(줄에 없으면 실시간 자동 폴백 — §11.4)
    var includeTranscript = true      // 끄면 회의록만 한 장으로(2026-09-11 B⑦) — 시트가 둘 다 끄는 조합을 막는다
    var removeFillers = false         // 군말 제거 — 내보내기 전용, 저장·화면 불변(기본 OFF)
    var replaceRules: [ReplaceRule] = []   // 치환 규칙 — 화면과 같은 값이 문서에도(규칙 4 단일 함수)
}

/// 세션 → TXT·MD·PDF·DOCX 파일 (본질 요소 ⑥·⑦ — 토글: 타임코드·화자 라벨·원문+번역).
enum SessionExporter {
    @MainActor
    static func run(session: Session, format: ExportFormat, options: ExportOptions) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.title).\(format.fileExtension)"
        panel.allowedContentTypes = [format.utType]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(session: session, format: format, options: options, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])   // 저장 확인 — Finder에서 보여주기
            } catch {
                NSLog("VV export: 실패 — %@", error.localizedDescription)   // 침묵 실패 금지
            }
        }
        #else
        // iOS: 임시 파일 → 공유 시트('파일에 저장'·AirDrop·앱 전달) — NSSavePanel 부재 (decisions §10)
        let safeTitle = session.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle).\(format.fileExtension)")
        do {
            try write(session: session, format: format, options: options, to: url)
            presentShareSheet(for: url)
        } catch {
            NSLog("VV export: 실패 — %@", error.localizedDescription)   // 침묵 실패 금지
        }
        #endif
    }

    /// 형식별 파일 생성 — macOS 저장 패널·iOS 공유 시트 공용 (규칙 4: 경로 단일화).
    private static func write(session: Session, format: ExportFormat, options: ExportOptions, to url: URL) throws {
        switch format {
        case .txt:
            try text(session, options, markdown: false).write(to: url, atomically: true, encoding: .utf8)
        case .md:
            try text(session, options, markdown: true).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try writePDF(attributed(session, options), to: url)
        case .docx:
            try DocxWriter.data(fromMarkdown: text(session, options, markdown: true))
                .write(to: url, options: .atomic)
        case .json:
            try jsonData(session, options).write(to: url, options: .atomic)
        }
    }

    // MARK: JSON — 공개 계약은 내부 Session과 분리(DTO). 내부 필드가 늘어도 이 스키마는 여기서만 바뀐다(파워유저 위원).

    private struct ExportDoc: Encodable {
        struct Item: Encodable { let text: String; let who: String?; let sourceTimecodes: [String] }
        struct Participant: Encodable { let speakerLabel: String; let name: String; let detail: String }
        struct Minutes: Encodable {
            let summary: String; let decisions: [Item]; let actionItems: [Item]; let participants: [Participant]
        }
        struct Segment: Encodable {
            let index: Int; let timecode: String; let speaker: String; let speakerUserSet: Bool; let typed: Bool
            let text: String; let translation: String?; let refinedTranslation: String?
        }
        let schema = "visualvoice.session.v1"
        let title: String; let createdAt: Date?; let displayDate: String; let languages: String
        let engine: String?; let model: String?; let segmentCount: Int; let duration: String
        let notes: [String]; let minutes: Minutes?; let transcript: [Segment]?
    }

    private static func jsonData(_ s: Session, _ o: ExportOptions) throws -> Data {
        var minutes: ExportDoc.Minutes? = nil
        if o.includeMinutes, case .ready(let m) = s.minutes {
            minutes = .init(
                summary: m.summary,
                decisions: m.decisions.map { .init(text: $0.text, who: nil, sourceTimecodes: $0.sourceTimecodes) },
                actionItems: m.actionItems.map { .init(text: $0.text, who: $0.who.isEmpty ? nil : $0.who, sourceTimecodes: $0.sourceTimecodes) },
                participants: m.participants.map { .init(speakerLabel: $0.speakerLabel, name: $0.displayName, detail: $0.detail) })
        }
        let transcript: [ExportDoc.Segment]? = o.includeTranscript ? (s.transcript ?? []).enumerated().map { i, l in
            .init(index: i + 1, timecode: l.timecode, speaker: l.speaker.label, speakerUserSet: l.speakerIsUserSet, typed: l.isTyped,
                  text: sourceText(l, o), translation: l.translation.isEmpty ? nil : l.translation,
                  refinedTranslation: l.refinedTranslation)
        } : nil
        let doc = ExportDoc(title: s.title, createdAt: s.createdAt, displayDate: s.displayDate, languages: s.pairShort,
                            engine: s.engineLabel, model: s.modelUsed, segmentCount: s.segments, duration: s.duration,
                            notes: s.notes ?? [], minutes: minutes, transcript: transcript)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(doc)
    }

    /// 녹취록 원문의 문서 표기 — 치환 규칙(화면과 동일) → 군말 제거(옵션). 저장 원문은 불변.
    private static func sourceText(_ line: CaptionLine, _ o: ExportOptions) -> String {
        var t = ReplaceRule.apply(line.source, rules: o.replaceRules)
        if o.removeFillers, !line.isTyped { t = ReplaceRule.removeFillers(t) }
        return t
    }

    #if os(iOS)
    /// 최상위 화면에서 공유 시트 표시 — iPad는 팝오버 앵커 필수(없으면 크래시).
    @MainActor
    private static func presentShareSheet(for url: URL) {
        // ponytail: 내보내기 시트 dismiss 애니메이션과의 경합 회피 — 0.6초 뒤 최상위 VC 탐색
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.keyWindow?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            avc.popoverPresentationController?.sourceView = top.view
            avc.popoverPresentationController?.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            avc.popoverPresentationController?.permittedArrowDirections = []
            top.present(avc, animated: true)
        }
    }
    #endif

    // MARK: 본문 구성

    private static func text(_ session: Session, _ o: ExportOptions, markdown: Bool) -> String {
        var out: [String] = []
        out.append(markdown ? "# \(session.title)" : session.title)
        out.append("\(session.displayDate) · \(session.pairShort) · \(session.segments)구간 · \(session.duration)"
                   + (session.engineLabel.map { " · \($0)" } ?? ""))
        if let notes = session.notes, !notes.isEmpty {   // 기록 조건도 문서에 — 제3자가 결손을 알 수 있게(§3)
            out.append("기록 조건: " + notes.joined(separator: " / "))
        }
        // AI 재번역 사용 시 마커 강제 — 제3자가 기계 재번역을 확정본으로 오인하지 않게(워게임 §D)
        let hasRefined = session.transcript?.contains { $0.refinedTranslation != nil } ?? false
        if o.useRefined && o.includeTranslation && hasRefined {
            out.append("번역: AI 재번역(온디바이스) · 세션 정지 후 생성 · ✦ = AI가 다시 번역한 줄")
        }
        out.append("")

        if o.includeMinutes, case .ready(let m) = session.minutes {
            out.append(markdown ? "## 회의록" : "== 회의록 ==")
            if !m.participants.isEmpty {
                out.append(markdown ? "### 참여 인원" : "[참여 인원]")
                for p in m.participants {   // '(추정)' 표기 제거(2026-07-18 · UI 배지 제거와 일관). 이름 미상은 추정값 시드.
                    let suffix = p.showsDetailSuffix ? " · \(p.detail)" : ""
                    out.append("- \(p.speakerLabel) — \(p.displayName)\(suffix)")
                }
            }
            out.append(markdown ? "### 요약" : "[요약]")
            out.append(m.summary)
            if !m.decisions.isEmpty {
                out.append(markdown ? "### 핵심 결정" : "[핵심 결정]")
                for d in m.decisions { out.append("- \(itemLine(d))") }
            }
            if !m.actionItems.isEmpty {
                out.append(markdown ? "### 할 일" : "[할 일]")
                for t in m.actionItems {
                    let head = markdown ? "- [ ] " : "- "
                    out.append("\(head)\(t.text)\(t.who.isEmpty ? "" : " — \(t.who)")\(trust(t))")
                }
            }
            out.append("")
        }

        if o.includeTranscript, let transcript = session.transcript {
            out.append(markdown ? "## 녹취록" : "== 녹취록 ==")
            for line in transcript {
                var parts: [String] = []
                if o.includeTimecode { parts.append("[\(line.timecode)]") }
                if o.includeSpeaker { parts.append("[\(line.speaker.label)\(line.isTyped ? "·타이핑" : "")]") }
                parts.append(sourceText(line, o))
                out.append((markdown ? "- " : "") + parts.joined(separator: " "))
                if o.includeTranslation {
                    // AI 재번역 우선 + 없는 줄은 실시간 자동 폴백(마커 ✦로 구분 — 부분 재번역 정직 표기)
                    let refined = o.useRefined ? line.refinedTranslation : nil
                    let tr = refined ?? line.translation
                    if !tr.isEmpty {
                        out.append((markdown ? "  - " : "    → ") + tr + (refined != nil ? " ✦" : ""))
                    }
                }
            }
        }
        out.append("")
        out.append("VisualVoice — 온디바이스 자막·녹취·회의록")
        return out.joined(separator: "\n")
    }

    private static func itemLine(_ item: MeetingMinutes.Item) -> String { "\(item.text)\(trust(item))" }

    /// 신뢰도 표기를 문서에도 유지 — 근거 타임코드 병기, 근거 없으면 '확인 필요' (조용한 확신 금지)
    private static func trust(_ item: MeetingMinutes.Item) -> String {
        item.sourceTimecodes.isEmpty ? " ※ 확인 필요"
                                     : " (근거 \(item.sourceTimecodes.joined(separator: ", ")))"
    }

    // MARK: PDF (A4 · CoreText 페이지네이션)

    private static func attributed(_ session: Session, _ o: ExportOptions) -> NSAttributedString {
        let body = text(session, o, markdown: false)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        // PDF 렌더(CGContext+CoreText)는 양 플랫폼 공용 — 글꼴·색 타입만 분기 (decisions §10 개정: UIGraphicsPDFRenderer 불필요)
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 11); let color = NSColor.black
        #else
        let font = UIFont.systemFont(ofSize: 11); let color = UIColor.black
        #endif
        return NSAttributedString(string: body, attributes: [
            .font: font,
            .foregroundColor: color,   // 문서는 인쇄물 — 다크 테마 아님
            .paragraphStyle: para,
        ])
    }

    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 (pt)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "VVExport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "PDF 컨텍스트 생성 실패"])
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: mediaBox.insetBy(dx: 42, dy: 46), transform: nil)
        var location = 0
        while location < text.length {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }   // 진전 없음 — 무한 루프 방지
            location += visible.length
        }
        ctx.closePDF()
    }
}
