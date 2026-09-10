import Foundation

/// 치환 규칙 — 인식기가 자주 틀리는 이름·브랜드·전문용어를 **표시·내보내기 시점에** 바로잡는다(2026-09-11 · §15.5-B⑤).
///
/// 저장된 원문(`CaptionLine.source`)은 절대 바꾸지 않는다 — §7 원문 보존, 그리고 §14 녹음 재전사 대조의
/// 기준선이 오염되면 분석 루프 자체가 무의미해진다. 확정 경로(`applyFinal`)·잠정 줄에도 넣지 않는다(§8 재발명 금지·깜빡임).
/// 엔진 레벨 어휘 주입(contextualStrings)은 Apple 경로 미지원이라 후처리 치환이 유일한 레버(decisions §2 사투리 항목).
struct ReplaceRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
    var wholeWord = true   // 단어 단위 — 문자·숫자 룩어라운드(한글·라틴 공용, `\b`는 한글에 안 든다 — 언어학자 위원)

    static let storageKey = "vv.replaceRules"

    static func load() -> [ReplaceRule] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let rules = try? JSONDecoder().decode([ReplaceRule].self, from: data) else { return [] }
        return rules
    }
    static func save(_ rules: [ReplaceRule]) {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    /// 위에서 아래 순서로 전부 적용. 빈 규칙은 건너뛴다.
    /// 단어 단위 — 라틴은 앞·뒤 경계 모두, **한글은 앞 경계만**: 조사·합성어가 띄어쓰기 없이 붙으므로("정크성은"·"삼송전자")
    /// 뒤 경계를 요구하면 실제 녹취록에서 거의 안 맞는다(2026-09-11 제작자 실측 "정크성→접근성이 기존 녹취록에 안 먹힘").
    static func apply(_ text: String, rules: [ReplaceRule]) -> String {
        var s = text
        for r in rules where !r.from.isEmpty {
            if r.wholeWord {
                let hangul = r.from.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: r.from)
                    + (hangul ? "" : "(?![\\p{L}\\p{N}])")
                s = s.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: r.to),
                                           options: [.regularExpression, .caseInsensitive])
            } else {
                s = s.replacingOccurrences(of: r.from, with: r.to, options: [.caseInsensitive])
            }
        }
        return s
    }

    #if DEBUG
    /// 자가 점검(하네스 `VV_PROBE_REPLACE=1`) — 규칙 로직이 깨지면 여기서 먼저 걸린다.
    static func selfTest() -> [String] {
        let ko = [ReplaceRule(from: "정크성", to: "접근성")], en = [ReplaceRule(from: "cat", to: "dog")]
        let cases: [(String, [ReplaceRule], String)] = [
            ("웹 정크성은 7월", ko, "웹 접근성은 7월"),           // 조사 붙음 → 치환
            ("정크성.", ko, "접근성."),                          // 문장 끝
            ("비정크성", ko, "비정크성"),                        // 앞에 글자 → 유지(앞 경계)
            ("the cat sat", en, "the dog sat"),
            ("category", en, "category"),                       // 라틴은 뒤 경계도 검사
            ("Cat!", en, "dog!"),                               // 대소문자 무시
        ]
        return cases.compactMap { input, rules, want in
            let got = apply(input, rules: rules)
            return got == want ? nil : "✗ \"\(input)\" → \"\(got)\" (기대 \"\(want)\")"
        }
    }
    #endif

    /// 군말 제거(내보내기 전용 · 기본 OFF) — 단독 토큰만: 한국어 음/어/저기, 인니어 anu/eee/hmm, 영어 um/uh/erm.
    /// '그'·'아'는 실단어("그 계약서")라 제외(언어학자 위원). 제거 후 ", ," 같은 구두점 잔재 정리.
    static func removeFillers(_ text: String) -> String {
        let fillers = "(?:음+|어+|저기|anu|eee+|hmm+|um+|uh+|erm?)"
        var s = text.replacingOccurrences(
            of: "(?<![\\p{L}\\p{N}])" + fillers + "(?![\\p{L}\\p{N}])[ \\t,]*",
            with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "([,;:])\\s*([.!?…])", with: "$2", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

#if DEBUG
extension ReplaceRule {
    static func runSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["VV_PROBE_REPLACE"] == "1" else { return }
        let fails = selfTest()
        print(fails.isEmpty ? "PROBE 치환 규칙 자가 점검 통과(6/6)" : "PROBE 치환 규칙 실패:\n" + fails.joined(separator: "\n"))
        exit(fails.isEmpty ? 0 : 1)
    }
}
#endif
