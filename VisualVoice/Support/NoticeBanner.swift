import SwiftUI

/// 상태 안내/경고 배너 — 청각으로 확인할 수 없는 사용자를 위한 시각 신호(안전②).
/// 라이브(가장자리 바)·홈·상세·셸(둥근 카드)이 공용(규칙 4 — 2026-09-11 세 곳으로 늘며 단일화).
struct NoticeBanner: View {
    enum Style { case bar, card }
    let text: String
    var color: Color = Theme.accent
    var icon: String = "info.circle"
    var style: Style = .bar

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).padding(.top, 1)
            Text(text).font(.system(size: 12, weight: .semibold)).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, style == .bar ? 22 : 14).padding(.vertical, style == .bar ? 7 : 10)
        .background(color.opacity(0.10), in: style == .bar ? AnyShape(Rectangle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
        .overlay {
            if style == .card { RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)) }
        }
    }
}
