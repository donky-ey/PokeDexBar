import SwiftUI

/// 아이템 그림. 알(`EggIcon`)·리본(`RibbonIcon`)은 그려 둔 PNG 를 싣지만, 사탕·쿠폰처럼 **단순한
/// 도형**은 코드로 그린다 — 바이너리 에셋이 안 늘고, 크기와 색을 상황마다 바꿀 수 있으며,
/// "실제로 무언가 그려졌나"를 테스트로 물어볼 수 있다(사용자 결정).
///
/// **연출이 SF Symbol 을 쓰던 것을 대신한다.** 약통(`pills.fill`)이 경험치 사탕이고 반짝이는
/// 손이 마사지 쿠폰이었는데, 손으로 그린 알 그림 옆에 시스템 글리프가 서니 따로 놀았다(사용자 지적).
struct ItemIcon: View {
    let item: ShopItem
    var size: CGFloat = 20

    /// 이 아이템에 무엇을 그리나. **순수 판정이라 테스트가 직접 물어본다** — 뷰 안에 묻어 두면
    /// "등급권이 알 그림으로 가는가" 같은 질문을 할 수가 없다.
    enum Drawing: Equatable {
        case candy
        case coupon
        /// 세대 확정권 — 같은 표 모양에 세대 숫자만 다르다.
        case generationTicket(Int)
        /// 등급 확정권 — **알이 아니라 알이 그려진 표**다. 처음엔 알 그림을 그대로 썼는데,
        /// 그러면 세대권은 표이고 등급권은 알이라 같은 확정권끼리 다른 물건처럼 보였다
        /// (사용자 지적). 손에 든 것은 알이 아니라 교환권이고, 알은 이걸 써야 나온다.
        case gradeTicket(Grade)
    }

    static func drawing(for item: ShopItem) -> Drawing? {
        if let grade = item.guaranteedGrade { return .gradeTicket(grade) }
        if let generation = item.guaranteedGeneration { return .generationTicket(generation) }
        switch item {
        case .expCandy: return .candy
        case .massageCoupon: return .coupon
        // 나머지 품목은 이번 범위 밖이다 — 대신 그릴 기본 도형을 두지 않는다. 아무거나 그리면
        // 틀린 그림이 조용히 서고, 없으면 빈 자리가 눈에 띄어 다음에 그릴 것이 드러난다.
        default: return nil
        }
    }

    /// 사탕 — 따뜻한 호박색. 알의 등급색과 안 겹치는 자리다.
    private static let candyColor = Color(red: 0.96, green: 0.72, blue: 0.32)
    /// 마사지 쿠폰 — 연한 장밋빛.
    private static let couponColor = Color(red: 0.93, green: 0.56, blue: 0.63)
    /// 세대권 — **종이색**이다. 처음엔 파랑이었는데 레어 등급색(`RevealStage.blue`)과 거의 같아,
    /// 등급권도 표가 되면서 둘이 구별이 안 됐다. 세대권이 말하는 것은 등급이 아니라 세대라,
    /// 등급색 어휘에서 비켜서는 편이 맞다 — 숫자가 내용을 맡는다.
    private static let generationColor = Color(red: 0.90, green: 0.87, blue: 0.78)

    /// 등급 확정권의 표 색 — 등급색은 `RevealStage` 가 이미 단일 소스로 갖고 있고, 여기서
    /// **흰쪽으로 섞어 연하게** 만든다. 원색 그대로 쓰면 그 위에 얹은 같은 등급의 알이 묻힌다
    /// (보라 위 보라가 특히 안 보였다). 표는 종이고 알이 인쇄물이라, 종이가 연한 편이 맞다.
    static func ticketColor(for grade: Grade) -> Color {
        let base = RevealStage.allCases.first { $0.grade == grade }?.color ?? .white
        guard let rgb = NSColor(base).usingColorSpace(.sRGB) else { return base }
        func paled(_ v: CGFloat) -> Double { Double(v + (1 - v) * Self.paleness) }
        return Color(red: paled(rgb.redComponent), green: paled(rgb.greenComponent),
                     blue: paled(rgb.blueComponent))
    }

    /// 흰쪽으로 섞는 정도. 0 이면 원색, 1 이면 흰색이다.
    private static let paleness: CGFloat = 0.52

    var body: some View {
        switch Self.drawing(for: item) {
        case .candy:
            CandyShape().fill(Self.candyColor).frame(width: size, height: size)
        case .coupon:
            ticket(Self.couponColor) { EmptyView() }
        case .generationTicket(let generation):
            ticket(Self.generationColor) {
                Text("\(generation)")
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.62))
                    .minimumScaleFactor(0.4)
            }
        case .gradeTicket(let grade):
            // 표 위에 **그 등급의 진짜 알 그림**을 얹는다 — 무엇을 보장하는 표인지 그림이 말한다.
            ticket(Self.ticketColor(for: grade)) {
                EggIcon(grade: grade, size: size * 0.40)
            }
        case nil:
            EmptyView()
        }
    }

    /// 표 한 장 — 좌우가 파인 둥근 사각형 + 점선 절취선. 쿠폰류가 이 한 문법을 공유하고
    /// 안에 든 것으로 갈린다.
    @ViewBuilder
    private func ticket<Content: View>(_ color: Color,
                                       @ViewBuilder content: () -> Content) -> some View {
        // 절취선과 내용물은 **나란한 형제**다. 처음엔 내용물을 절취선의 `.overlay` 안에 중첩시켰다가
        // 세대 숫자가 아예 안 그려졌다(쿠폰과 세대권의 픽셀이 한 개도 안 달랐다).
        ZStack {
            TicketShape().fill(color, style: TicketShape.fillStyle)
            // 절취선은 파인 곳 사이를 잇는다 — 표라는 것이 도형만으로 안 읽힐 때 이 한 줄이 말해 준다.
            Path { path in
                path.move(to: CGPoint(x: size * 0.70, y: size * 0.30))
                path.addLine(to: CGPoint(x: size * 0.70, y: size * 0.70))
            }
            .stroke(.black.opacity(0.30),
                    style: StrokeStyle(lineWidth: max(0.5, size * 0.035),
                                       dash: [max(1, size * 0.06)]))
            // 숫자는 절취선 **왼쪽** 본판에 앉는다 — 표에서 내용이 적히는 자리다.
            content()
                .frame(width: size * 0.56, alignment: .center)
                .offset(x: -size * 0.16)
        }
        .frame(width: size, height: size)
    }
}

/// 포장지가 양쪽으로 꼬인 사탕. 20pt 에서도 안 뭉개지는 몇 안 되는 실루엣이다.
struct CandyShape: Shape {
    func path(in rect: CGRect) -> Path {
        // **크기로 나누지 않는다** — 0 이 들어오면 NaN 이 되고, 그 값이 변환으로 내려가면
        // AppKit 이 프로세스를 abort 시킨다(이 저장소의 특이행렬 전례). 전부 곱셈이다.
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.24, y: rect.minY + h * 0.22,
                                   width: w * 0.52, height: h * 0.56))
        // 포장지는 **몸통보다 낮고, 바깥 끝이 V 로 파인다.** 처음엔 몸통과 같은 높이에 바깥을
        // 둥글게 했더니 원을 베어 문 것처럼 보였다 — 사탕이 아니라 나비넥타이였다.
        for side in [CGFloat(1), -1] {
            func x(_ v: CGFloat) -> CGFloat { side > 0 ? v : 1 - v }
            path.move(to: p(x(0.32), 0.40))
            path.addLine(to: p(x(0.05), 0.27))
            path.addLine(to: p(x(0.12), 0.50))   // 바깥 끝의 V 홈 — 꼬인 포장지의 신호다
            path.addLine(to: p(x(0.05), 0.73))
            path.addLine(to: p(x(0.32), 0.60))
            path.closeSubpath()
        }
        return path
    }
}

/// 표(쿠폰) — 좌우 변이 반원으로 파인 둥근 사각형. 구멍은 **짝홀 규칙으로 실제로 뚫는다**;
/// 배경색 원을 덮으면 어두운 연출 위에서는 맞고 밝은 화면에서는 틀린다.
struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path(roundedRect: CGRect(x: rect.minX + w * 0.04, y: rect.minY + h * 0.24,
                                            width: w * 0.92, height: h * 0.52),
                        cornerRadius: min(w, h) * 0.08)
        let notch = min(w, h) * 0.11
        for x in [rect.minX + w * 0.04, rect.minX + w * 0.96] {
            path.addEllipse(in: CGRect(x: x - notch, y: rect.midY - notch,
                                       width: notch * 2, height: notch * 2))
        }
        return path
    }

    /// 구멍이 실제로 뚫리도록 — 기본 `.nonZero` 로는 원이 사각형을 덮어 칠해진다.
    static var fillStyle: FillStyle { FillStyle(eoFill: true) }
}
