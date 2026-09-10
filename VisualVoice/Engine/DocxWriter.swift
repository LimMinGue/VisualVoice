import Foundation

/// 세션 녹취록·회의록 → .docx (OOXML) — 무의존 생성 (decisions §30, 2026-07-18).
/// 본문은 `SessionExporter.text(markdown:true)`를 그대로 중간표현으로 재사용한다 — 기존 TXT/MD/PDF
/// 빌더는 한 줄도 건드리지 않고, 마크다운 접두어(`#`/`##`/`- ` 등)만 Word 문단 스타일로 매핑한다.
/// ZIP은 store(무압축)+CRC32 손구현 — macOS에 공개 ZIP 쓰기 API가 없고 NSFileCoordinator는 항목을
/// 폴더 아래로 중첩시켜 OOXML 루트 규약에 못 맞으므로(위원회 2026-07-18).
enum DocxWriter {

    /// 마크다운 문자열 → .docx 바이트.
    static func data(fromMarkdown md: String) -> Data {
        let document = documentTemplate.replacingOccurrences(of: "{{BODY}}",
                                                             with: paragraphsXML(fromMarkdown: md))
        // OOXML 최소 3파트 — 전부 ZIP 루트 기준 경로여야 Word가 연다.
        return Zip.archive([
            (name: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            (name: "_rels/.rels",         data: Data(relsXML.utf8)),
            (name: "word/document.xml",   data: Data(document.utf8)),
        ])
    }

    // MARK: 마크다운 → WordprocessingML 문단

    private enum Style { case title, heading1, heading2, bullet, translation }

    private static func paragraphsXML(fromMarkdown md: String) -> String {
        var out = ""
        var inTranscript = false   // '## 녹취록' 이후 구간 — 발화 줄은 타임코드/화자 토글과 무관하게 흐르는 본문
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line == "## 녹취록" { inTranscript = true }
            else if line.hasPrefix("## ") { inTranscript = false }
            out += mapLine(line, inTranscript: inTranscript)
        }
        return out
    }

    private static func mapLine(_ line: String, inTranscript: Bool) -> String {
        if line.isEmpty                  { return paragraph("", style: nil) }        // 빈 줄 = 간격 문단
        if let t = strip(line, "# ")     { return paragraph(t, style: .title) }
        if let t = strip(line, "## ")    { return paragraph(t, style: .heading1) }
        if let t = strip(line, "### ")   { return paragraph(t, style: .heading2) }
        if let t = strip(line, "- [ ] ") { return paragraph(t, style: .bullet) }     // 할 일 체크박스
        if let t = strip(line, "  - ")   { return paragraph(t, style: .translation) } // 번역 들여쓰기
        // 녹취록 발화 = 흐르는 본문 — 타임코드/화자 토글을 다 꺼 "- [" 대괄호가 없어도 구간으로 판정(검증 확증)
        if inTranscript, let t = strip(line, "- ") { return paragraph(t, style: nil) }
        if let t = strip(line, "- ")     { return paragraph(t, style: .bullet) }     // 회의록 결정·참여자 = 불릿
        return paragraph(line, style: nil)                                           // 메타·푸터 = 본문
    }

    private static func strip(_ line: String, _ prefix: String) -> String? {
        line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
    }

    /// <w:p> 한 문단 — 스타일별 크기·굵기·색·들여쓰기를 인라인 속성으로 (별도 styles.xml 불필요).
    /// ponytail: 진짜 리스트 넘버링(numbering.xml)은 무의존 유지 위해 • 글머리 글자로 대체.
    private static func paragraph(_ text: String, style: Style?) -> String {
        var pPr = "", rPr = "", bullet = ""
        switch style {
        case .title:       pPr = spacing(before: 240, after: 120); rPr = "<w:b/><w:sz w:val=\"36\"/>"  // 18pt
        case .heading1:    pPr = spacing(before: 200, after: 80);  rPr = "<w:b/><w:sz w:val=\"28\"/>"  // 14pt
        case .heading2:    pPr = spacing(before: 160, after: 60);  rPr = "<w:b/><w:sz w:val=\"24\"/>"  // 12pt
        case .bullet:      pPr = "<w:ind w:left=\"360\"/>"; bullet = "•  "
        case .translation: pPr = "<w:ind w:left=\"600\"/>"; rPr = "<w:i/><w:color w:val=\"666666\"/>"
        case nil:          break
        }
        let run = text.isEmpty ? ""
            : "<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(bullet)\(xmlEscape(text))</w:t></w:r>"
        return "<w:p><w:pPr>\(pPr)</w:pPr>\(run)</w:p>"
    }

    private static func spacing(before: Int, after: Int) -> String {
        "<w:spacing w:before=\"\(before)\" w:after=\"\(after)\"/>"
    }

    /// XML 1.0 이스케이프 — & < > " 치환 + 유효하지 않은 제어문자 폐기(파일 손상 방지, QC 조건).
    private static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 8)
        for ch in s.unicodeScalars {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "\n", "\r": out += " "                       // 문단 내 개행은 공백(문단 분리는 이미 완료)
            default:
                if ch.value >= 0x20 || ch.value == 0x09 { out.unicodeScalars.append(ch) }
            }
        }
        return out
    }

    // MARK: OOXML 파트 템플릿

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    </Types>
    """

    private static let relsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    </Relationships>
    """

    // A4(11906×16838 twip) · 여백 ~2cm(1134 twip). sectPr는 body 끝.
    private static let documentTemplate = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{{BODY}}\
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>\
    </w:body></w:document>
    """
}

/// 최소 store(무압축) ZIP 라이터 + CRC32 — DOCX(OOXML) 컨테이너 전용 (무의존).
enum Zip {
    static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data(), central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)          // 경로 길이는 '바이트' 기준(문자 수 아님 — 비ASCII 안전)
            let crc = Self.crc32(entry.data)
            let size = UInt32(entry.data.count)
            let nameLen = UInt16(nameBytes.count)
            let headerOffset = offset

            var local = Data()
            local.append(le32: 0x04034b50)   // 로컬 파일 헤더 시그니처
            local.append(le16: 20)           // version needed
            local.append(le16: 0)            // general purpose flags
            local.append(le16: 0)            // method 0 = store(무압축)
            local.append(le16: 0)            // mod time
            local.append(le16: 0x21)         // mod date = 1980-01-01(Word 무관, 결정론적)
            local.append(le32: crc)
            local.append(le32: size)         // compressed = uncompressed (store)
            local.append(le32: size)
            local.append(le16: nameLen)
            local.append(le16: 0)            // extra len
            local.append(nameBytes)
            out.append(local)
            out.append(entry.data)
            offset += UInt32(local.count) + size

            central.append(le32: 0x02014b50) // 중앙 디렉터리 헤더 시그니처
            central.append(le16: 20)         // version made by
            central.append(le16: 20)         // version needed
            central.append(le16: 0)
            central.append(le16: 0)          // method
            central.append(le16: 0)
            central.append(le16: 0x21)
            central.append(le32: crc)
            central.append(le32: size)
            central.append(le32: size)
            central.append(le16: nameLen)
            central.append(le16: 0)          // extra
            central.append(le16: 0)          // comment
            central.append(le16: 0)          // disk number start
            central.append(le16: 0)          // internal attrs
            central.append(le32: 0)          // external attrs
            central.append(le32: headerOffset)
            central.append(nameBytes)
        }

        let centralOffset = offset
        out.append(central)

        out.append(le32: 0x06054b50)         // EOCD 시그니처
        out.append(le16: 0)                  // disk number
        out.append(le16: 0)                  // cd start disk
        out.append(le16: UInt16(entries.count))
        out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)                  // comment len
        return out
    }

    /// CRC32 (ISO 3309 / ZIP 표준, 반사 다항식 0xEDB88320). ponytail: 비트별 계산 — 내보내기는
    /// 일회성 사용자 액션이라 룩업 테이블 불필요(수백 KB에도 <10ms).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(le16 v: UInt16) { append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8)]) }
    mutating func append(le32 v: UInt32) {
        append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    }
}
