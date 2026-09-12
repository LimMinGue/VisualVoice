import SwiftUI

/// 기록 보관함 — 전체 세션 카드 리스트 + 전문 검색.
/// 클릭 → 기존 SessionDetailView(openDetail) · 삭제 → 확인 다이얼로그(기존 패턴 재사용).
struct ArchiveView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @State private var pendingDelete: Session?

    /// 전문 검색 — 제목·미리보기·녹취록 내용(원문+번역). 최신순은 app.sessions 순서 그대로(삽입이 0번).
    private var filtered: [Session] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return app.sessions }
        return app.sessions.filter { s in
            if s.title.lowercased().contains(q) || s.preview.lowercased().contains(q) { return true }
            return (s.transcript ?? []).contains {
                $0.source.lowercased().contains(q) || $0.translation.lowercased().contains(q)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("기록 보관함").font(.system(size: 22, weight: .bold))
                    Text("\(app.sessions.count)개 세션").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3).font(.system(size: 13))
                    TextField("제목·내용으로 검색…", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hair))

                if app.sessions.isEmpty {
                    empty("아직 저장된 세션이 없습니다.", "세션을 진행하면 여기에 녹취록과 회의록이 쌓입니다.")
                } else if filtered.isEmpty {
                    empty("검색 결과가 없습니다.", "‘\(query)’와 일치하는 세션을 찾지 못했습니다.")
                } else {
                    VStack(spacing: 10) { ForEach(filtered) { card($0) } }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("‘\(pendingDelete?.title ?? "")’ 세션을 삭제할까요?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) { if let s = pendingDelete { app.delete(s) }; pendingDelete = nil }
            Button("취소", role: .cancel) { pendingDelete = nil }
        } message: { Text(app.deleteWarning(for: pendingDelete)) }
    }

    private func card(_ s: Session) -> some View {
        Button { app.openDetail(s) } label: { cardBody(s) }   // 진짜 Button — 접근성 API·VoiceOver 대응(2026-09-11)
            .buttonStyle(.plain)
            .accessibilityLabel("\(s.title), \(s.displayDate)")
    }

    private func cardBody(_ s: Session) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(s.dotColor).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(s.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(s.displayDate) · \(s.pairShort) · \(s.segments)구간 · \(s.duration)")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                if !s.preview.isEmpty {
                    Text(s.preview).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                minutesBadge(s.minutes)
            }
            Spacer(minLength: 8)
            Button { pendingDelete = s } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    .frame(width: 28, height: 28)
            }.buttonStyle(.plain).help("삭제")
        }
        .padding(14)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hair))
        .contentShape(Rectangle())   // 카드 전체가 버튼(삭제 버튼은 자체 영역 캡처 — 사이드바 패턴)
    }

    @ViewBuilder private func minutesBadge(_ m: MinutesState) -> some View {
        switch m {
        case .ready:      badge("회의록", Theme.accent, Theme.accentDim)
        case .generating: badge("회의록 생성 중", Theme.ink3, Color.clear)
        default:          EmptyView()
        }
    }
    private func badge(_ t: String, _ fg: Color, _ bg: Color) -> some View {
        Text(t).font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(fg).padding(.horizontal, 9).padding(.vertical, 2)
            .background(bg, in: Capsule()).overlay(Capsule().stroke(fg.opacity(0.35)))
    }
    private func empty(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
            Text(desc).font(.system(size: 12)).foregroundStyle(Theme.ink3)
        }.padding(.vertical, 40)
    }
}
