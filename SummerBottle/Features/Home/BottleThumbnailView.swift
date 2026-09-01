//
//  BottleThumbnailView.swift
//  SummerBottle
//
//  2Dのスタイライズドボトルサムネイル(SwiftUI描画、3D不使用)。
//  ホームの棚とカレンダーの両方から使われる。
//

import SwiftUI

// MARK: - サムネイル本体

/// ボトル1本を2Dシルエットで描くサムネイル。
/// bottleType ごとの瓶シルエット + 空色→代表色→砂色のグラデ中身 + ガラスのハイライト。
struct BottleThumbnailView: View {
    let bottle: Bottle
    let height: CGFloat

    init(bottle: Bottle, height: CGFloat) {
        self.bottle = bottle
        self.height = height
    }

    private var type: BottleType { bottle.bottleType }
    private var isNight: Bool { bottle.timeOfDay == .night }

    /// 小瓶は同じ枠内でも少し小さく描く
    private var drawnHeight: CGFloat {
        type == .mini ? height * 0.72 : height
    }

    /// 瓶ごとの縦横比(幅 / 高さ)
    private var aspectRatio: CGFloat {
        switch type {
        case .standard: 0.52
        case .round: 0.72
        case .mini: 0.64
        case .lantern: 0.58
        case .drift: 0.50
        case .soda: 0.36
        }
    }

    private var drawnWidth: CGFloat { drawnHeight * aspectRatio }

    private var silhouette: ShelfBottleSilhouette { ShelfBottleSilhouette(type: type) }

    /// 夜の発光色(ランタンは暖色)
    private var glowColor: Color {
        type == .lantern ? Color(hex: "#FFB347") : Color(hex: "#FFE9A8")
    }

    var body: some View {
        ZStack {
            glassInterior
            glassOverlay
        }
        .frame(width: drawnWidth, height: drawnHeight)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.16), radius: 2, x: 0, y: 2)
        .shadow(color: isNight ? glowColor.opacity(0.75) : Color.clear, radius: isNight ? 8 : 0)
        .overlay(alignment: .topTrailing) {
            if bottle.isFavorite {
                favoriteBadge
                    .offset(x: 3, y: -3)
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    // MARK: 中身

    /// 空色 → 代表色 → 砂色の縦グラデ + 白い波の曲線
    private var glassInterior: some View {
        ZStack {
            silhouette.fill(interiorGradient)
            Group {
                ThumbnailWaveShape(baseline: 0.56)
                    .stroke(Color.white.opacity(0.55), lineWidth: max(1, height * 0.008))
                ThumbnailWaveShape(baseline: 0.64)
                    .stroke(Color.white.opacity(0.35), lineWidth: max(0.8, height * 0.006))
            }
            .clipShape(silhouette)
            // ガラス越しのうっすらした膜
            silhouette.fill(Color.white.opacity(0.07))
        }
    }

    private var interiorGradient: LinearGradient {
        let sky = Color(hex: bottle.sceneConfig.skyColorHex)
        let representative = Color(hex: bottle.representativeColorHex)
        return LinearGradient(
            stops: [
                .init(color: sky, location: 0.0),
                .init(color: sky, location: 0.30),
                .init(color: representative, location: 0.62),
                .init(color: AppTheme.sand, location: 0.88),
                .init(color: AppTheme.sand, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    // MARK: ガラスと装飾

    private var glassOverlay: some View {
        ZStack {
            // 輪郭
            silhouette.stroke(AppTheme.glassTint.opacity(0.9), lineWidth: max(1, height * 0.008))
            // ガラスのハイライト(白の細いカプセル)
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: max(2.5, drawnWidth * 0.08), height: drawnHeight * 0.32)
                .rotationEffect(.degrees(7))
                .offset(x: -drawnWidth * 0.24, y: -drawnHeight * 0.10)
            decoration
        }
    }

    /// 瓶の種類ごとの小さな装飾(栓・ビー玉・枠など)
    @ViewBuilder
    private var decoration: some View {
        switch type {
        case .standard:
            // 銀色のキャップ
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "#C9CED6"))
                .frame(width: drawnWidth * 0.36, height: drawnHeight * 0.055)
                .offset(y: -drawnHeight * 0.475)
        case .mini:
            // 小さなコルク
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "#B98A5E"))
                .frame(width: drawnWidth * 0.42, height: drawnHeight * 0.06)
                .offset(y: -drawnHeight * 0.475)
        case .round:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "#B98A5E"))
                .frame(width: drawnWidth * 0.28, height: drawnHeight * 0.05)
                .offset(y: -drawnHeight * 0.475)
        case .drift:
            // コルク栓
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(hex: "#A97B50"))
                .frame(width: drawnWidth * 0.32, height: drawnHeight * 0.10)
                .offset(y: -drawnHeight * 0.425)
            // 古紙風ラベル
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: "#F3E6C8").opacity(0.9))
                .frame(width: drawnWidth * 0.50, height: drawnHeight * 0.14)
                .rotationEffect(.degrees(-4))
                .offset(y: drawnHeight * 0.18)
        case .soda:
            // ビー玉
            ZStack {
                Circle().fill(Color(hex: "#BEE3F0").opacity(0.95))
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .scaleEffect(0.3)
                    .offset(x: -drawnWidth * 0.04, y: -drawnWidth * 0.04)
            }
            .frame(width: drawnWidth * 0.30, height: drawnWidth * 0.30)
            .offset(y: -drawnHeight * 0.30)
        case .lantern:
            // 枠(縦桟)
            HStack(spacing: 0) {
                Rectangle().frame(width: max(1, drawnWidth * 0.03))
                Spacer()
                Rectangle().frame(width: max(1, drawnWidth * 0.03))
            }
            .foregroundStyle(Color(hex: "#6B4A2F").opacity(0.55))
            .frame(width: drawnWidth * 0.52, height: drawnHeight * 0.78)
            .offset(y: drawnHeight * 0.075)
            // 吊り輪
            Circle()
                .stroke(Color(hex: "#6B4A2F"), lineWidth: max(1, drawnWidth * 0.03))
                .frame(width: drawnWidth * 0.16, height: drawnWidth * 0.16)
                .offset(y: -drawnHeight * 0.48)
        }
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: max(9, height * 0.10)))
            .foregroundStyle(Color(hex: "#FF4D6D"))
            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 0.5)
    }
}

// MARK: - 瓶のシルエット形状

/// bottleType ごとの瓶シルエット(Path描画)。
/// ホームの棚の空瓶イラストやボタンアイコンにも流用される。
struct ShelfBottleSilhouette: Shape {
    let type: BottleType

    nonisolated func path(in rect: CGRect) -> Path {
        switch type {
        case .standard:
            return shoulderedBottle(in: rect, neckHalf: 0.17, neckTop: 0.02, neckBottom: 0.16, shoulder: 0.30, corner: 0.10)
        case .mini:
            return shoulderedBottle(in: rect, neckHalf: 0.20, neckTop: 0.02, neckBottom: 0.18, shoulder: 0.34, corner: 0.14)
        case .drift:
            return shoulderedBottle(in: rect, neckHalf: 0.15, neckTop: 0.10, neckBottom: 0.24, shoulder: 0.38, corner: 0.10)
        case .round:
            return roundBottle(in: rect)
        case .soda:
            return sodaBottle(in: rect)
        case .lantern:
            return lanternBottle(in: rect)
        }
    }

    /// 肩付き瓶(standard / mini / drift 共通のベース)
    private nonisolated func shoulderedBottle(
        in rect: CGRect,
        neckHalf: CGFloat,
        neckTop: CGFloat,
        neckBottom: CGFloat,
        shoulder: CGFloat,
        corner: CGFloat
    ) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        let neckL = x0 + w * (0.5 - neckHalf)
        let neckR = x0 + w * (0.5 + neckHalf)
        let top = y0 + h * neckTop
        let neckBottomY = y0 + h * neckBottom
        let shoulderY = y0 + h * shoulder
        let bodyL = x0 + w * 0.05
        let bodyR = x0 + w * 0.95
        let bottom = y0 + h * 0.98
        let cr = w * corner

        var p = Path()
        p.move(to: CGPoint(x: neckL, y: top))
        p.addLine(to: CGPoint(x: neckL, y: neckBottomY))
        p.addCurve(
            to: CGPoint(x: bodyL, y: shoulderY),
            control1: CGPoint(x: neckL, y: neckBottomY + (shoulderY - neckBottomY) * 0.55),
            control2: CGPoint(x: bodyL, y: neckBottomY + (shoulderY - neckBottomY) * 0.45))
        p.addLine(to: CGPoint(x: bodyL, y: bottom - cr))
        p.addQuadCurve(to: CGPoint(x: bodyL + cr, y: bottom), control: CGPoint(x: bodyL, y: bottom))
        p.addLine(to: CGPoint(x: bodyR - cr, y: bottom))
        p.addQuadCurve(to: CGPoint(x: bodyR, y: bottom - cr), control: CGPoint(x: bodyR, y: bottom))
        p.addLine(to: CGPoint(x: bodyR, y: shoulderY))
        p.addCurve(
            to: CGPoint(x: neckR, y: neckBottomY),
            control1: CGPoint(x: bodyR, y: neckBottomY + (shoulderY - neckBottomY) * 0.45),
            control2: CGPoint(x: neckR, y: neckBottomY + (shoulderY - neckBottomY) * 0.55))
        p.addLine(to: CGPoint(x: neckR, y: top))
        p.addQuadCurve(to: CGPoint(x: neckL, y: top), control: CGPoint(x: x0 + w * 0.5, y: top - h * 0.015))
        p.closeSubpath()
        return p
    }

    /// 丸型ボトル(球体 + 短い首)
    private nonisolated func roundBottle(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: x0 + w * fx, y: y0 + h * fy)
        }
        var p = Path()
        p.move(to: pt(0.37, 0.02))
        p.addLine(to: pt(0.37, 0.20))
        p.addCurve(to: pt(0.03, 0.60), control1: pt(0.28, 0.22), control2: pt(0.03, 0.38))
        p.addCurve(to: pt(0.50, 0.98), control1: pt(0.03, 0.84), control2: pt(0.26, 0.98))
        p.addCurve(to: pt(0.97, 0.60), control1: pt(0.74, 0.98), control2: pt(0.97, 0.84))
        p.addCurve(to: pt(0.63, 0.20), control1: pt(0.97, 0.38), control2: pt(0.72, 0.22))
        p.addLine(to: pt(0.63, 0.02))
        p.addQuadCurve(to: pt(0.37, 0.02), control: pt(0.50, 0.005))
        p.closeSubpath()
        return p
    }

    /// 炭酸瓶(ラムネ風の細長 + くびれ)
    private nonisolated func sodaBottle(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: x0 + w * fx, y: y0 + h * fy)
        }
        var p = Path()
        p.move(to: pt(0.34, 0.02))
        p.addLine(to: pt(0.34, 0.12))
        p.addQuadCurve(to: pt(0.10, 0.22), control: pt(0.12, 0.13))
        p.addCurve(to: pt(0.22, 0.38), control1: pt(0.10, 0.28), control2: pt(0.22, 0.31))
        p.addCurve(to: pt(0.08, 0.55), control1: pt(0.22, 0.45), control2: pt(0.08, 0.47))
        p.addLine(to: pt(0.08, 0.92))
        p.addQuadCurve(to: pt(0.16, 0.98), control: pt(0.08, 0.98))
        p.addLine(to: pt(0.84, 0.98))
        p.addQuadCurve(to: pt(0.92, 0.92), control: pt(0.92, 0.98))
        p.addLine(to: pt(0.92, 0.55))
        p.addCurve(to: pt(0.78, 0.38), control1: pt(0.92, 0.47), control2: pt(0.78, 0.45))
        p.addCurve(to: pt(0.90, 0.22), control1: pt(0.78, 0.31), control2: pt(0.90, 0.28))
        p.addQuadCurve(to: pt(0.66, 0.12), control: pt(0.88, 0.13))
        p.addLine(to: pt(0.66, 0.02))
        p.addQuadCurve(to: pt(0.34, 0.02), control: pt(0.50, 0.005))
        p.closeSubpath()
        return p
    }

    /// ランタンボトル(角丸の胴 + ドーム状の頭)
    private nonisolated func lanternBottle(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: x0 + w * fx, y: y0 + h * fy)
        }
        let cfx: CGFloat = 0.12
        let cfy: CGFloat = 0.055
        var p = Path()
        p.move(to: pt(0.34, 0.05))
        p.addLine(to: pt(0.34, 0.16))
        p.addLine(to: pt(0.06 + cfx, 0.16))
        p.addQuadCurve(to: pt(0.06, 0.16 + cfy), control: pt(0.06, 0.16))
        p.addLine(to: pt(0.06, 0.98 - cfy))
        p.addQuadCurve(to: pt(0.06 + cfx, 0.98), control: pt(0.06, 0.98))
        p.addLine(to: pt(0.94 - cfx, 0.98))
        p.addQuadCurve(to: pt(0.94, 0.98 - cfy), control: pt(0.94, 0.98))
        p.addLine(to: pt(0.94, 0.16 + cfy))
        p.addQuadCurve(to: pt(0.94 - cfx, 0.16), control: pt(0.94, 0.16))
        p.addLine(to: pt(0.66, 0.16))
        p.addLine(to: pt(0.66, 0.05))
        p.addQuadCurve(to: pt(0.34, 0.05), control: pt(0.50, 0.01))
        p.closeSubpath()
        return p
    }
}

// MARK: - 波の曲線

/// 瓶の中の小さな白い波(横一列のうねり)
private struct ThumbnailWaveShape: Shape {
    let baseline: CGFloat // 0...1(高さ方向の位置)

    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.minY + rect.height * baseline
        let amplitude = rect.height * 0.018
        let segments = 3
        let segWidth = rect.width / CGFloat(segments)
        p.move(to: CGPoint(x: rect.minX, y: y))
        for i in 0..<segments {
            let startX = rect.minX + segWidth * CGFloat(i)
            let direction: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            p.addQuadCurve(
                to: CGPoint(x: startX + segWidth, y: y),
                control: CGPoint(x: startX + segWidth / 2, y: y + direction * amplitude * 2))
        }
        return p
    }
}
