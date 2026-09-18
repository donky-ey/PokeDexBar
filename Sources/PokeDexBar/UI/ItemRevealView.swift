import SwiftUI

/// 박사의 상자 결과 연출 — 알 뽑기와 **같은 무대**(`RevealTheater`)를 쓰고, 가운데 그림과
/// 결과 줄만 아이템의 것으로 바꾼다.
struct ItemRevealView: View {
    let result: ItemDrawResult
    let l: L
    let language: AppLanguage
    let onDone: () -> Void

    /// 그 아이템을 가리키는 SF Symbol. **알 확정권은 nil** — 이미 있는 알 그림이 더 말이 된다.
    /// 여기 쓰는 것은 전부 SF Symbols 1.0/2.0 세대라 macOS 14 바닥에도 있다. 테스트가 그것을
    /// 픽스처가 아니라 `NSImage(systemSymbolName:)` 에 직접 물어 확인한다.
    static func symbolName(for item: ShopItem) -> String? {
        if item.guaranteedGrade != nil || item.guaranteedGeneration != nil { return nil }
        switch item {
        case .massageCoupon: return "hands.sparkles.fill"
        default: return "pills.fill"
        }
    }

    var body: some View {
        RevealTheater(grade: result.rarity, onDone: onDone) { moment in
            glyph(moment)
        } result: { stage in
            VStack(spacing: 3) {
                Text(result.count > 1
                     ? "\(result.item.label(language)) \(l.itemDrawCount(result.count))"
                     : result.item.label(language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stage.color)
                    .multilineTextAlignment(.center)
                Text(l.itemDrawLanded).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    /// 가운데 그림. 확정권은 알 그림, 나머지는 심볼이다.
    @ViewBuilder
    private func glyph(_ moment: RevealBeat) -> some View {
        Group {
            if let grade = result.item.guaranteedGrade {
                EggIcon(grade: grade, size: 78)
            } else if result.item.guaranteedGeneration != nil {
                // 세대권은 등급이 안 정해져 있다 — 등급 없는 알(실루엣) 위에 세대 숫자를 얹는다.
                EggIcon(grade: .common, size: 78)
                    .opacity(0)
                    .overlay {
                        if let art = EggIcon.image(for: .common) {
                            Image(nsImage: art).resizable().renderingMode(.template)
                                .interpolation(.high).scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Text("\(result.item.guaranteedGeneration ?? 0)")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                    }
            } else if let name = Self.symbolName(for: result.item) {
                Image(systemName: name)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(moment.burst ? 1.12 : 0.94)
        .shadow(color: moment.stage.color.opacity(0.85), radius: moment.burst ? 22 : 8)
        .animation(.spring(duration: 0.3), value: moment.beat)
    }
}
