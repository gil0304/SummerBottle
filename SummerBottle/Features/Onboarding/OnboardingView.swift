//
//  OnboardingView.swift
//  SummerBottle
//
//  初回起動時のオンボーディング。4ページ構成:
//  ①コンセプト ②作り方 ③鑑賞 ④ARと書き出し+「はじめる」
//

import SwiftUI

struct OnboardingView: View {
    private let onFinish: () -> Void
    @State private var page: Int = 0

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#4FA8D8"), AppTheme.ocean, AppTheme.deepSea],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // スキップ(常設)
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap()
                        onFinish()
                    } label: {
                        Text("スキップ")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                TabView(selection: $page) {
                    conceptPage.tag(0)
                    howToPage.tag(1)
                    viewingPage.tag(2)
                    arAndStartPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 28)
            }
        }
    }

    // MARK: - ページドット

    private var pageDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    // MARK: - ① コンセプト

    private var conceptPage: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 8)

            OnboardingBottleIllustration()

            Text("夏の一日を、\n小さな瓶の中に閉じ込める。")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineSpacing(6)

            Text("Summer Bottle は、その日の写真と音から\nあなたの夏を小さな3Dボトルにする\n思い出アプリです。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - ② 作り方

    private var howToPage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Text("ボトルの作り方")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("3つのステップで、今日が一本の瓶になります。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                stepRow(number: 1, icon: "photo.on.rectangle.angled",
                        title: "写真を選ぶ",
                        detail: "その日の写真を1〜10枚選びます")
                stepArrow
                stepRow(number: 2, icon: "square.and.pencil",
                        title: "情報を入れる",
                        detail: "タイトル・場所・ひとことを添えます")
                stepArrow
                stepRow(number: 3, icon: "wand.and.stars",
                        title: "ボトル生成",
                        detail: "写真を解析して、瓶の中に夏のジオラマが生まれます")
            }
            .padding(.top, 8)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
    }

    private var stepArrow: some View {
        Image(systemName: "arrow.down")
            .font(.caption.bold())
            .foregroundStyle(.white.opacity(0.6))
    }

    private func stepRow(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.coral)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("STEP \(number)  \(title)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - ③ 鑑賞

    private var viewingPage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Text("できたボトルを、たのしむ")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("瓶の中の夏は、手のひらの上で生きています。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                gestureRow(icon: "hand.draw.fill",
                           title: "ドラッグで回転",
                           detail: "指でなぞると360度どこからでも眺められます")
                gestureRow(icon: "iphone",
                           title: "傾けると中がゆれる",
                           detail: "端末を傾けると水面や雲がゆらめきます")
                gestureRow(icon: "iphone.radiowaves.left.and.right",
                           title: "シェイクで演出",
                           detail: "振ると水しぶきや花火の光が舞います")
                gestureRow(icon: "speaker.wave.2.fill",
                           title: "栓を開けると音",
                           detail: "コルクを開けると、その日の音があふれ出します")
            }
            .padding(.top, 8)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
    }

    private func gestureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppTheme.sand)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - ④ ARと書き出し+はじめる

    private var arAndStartPage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Text("部屋に置く、かたちに残す")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 14) {
                gestureRow(icon: "arkit",
                           title: "ARで部屋に置く",
                           detail: "実物大のボトルをテーブルの上に飾れます")
                gestureRow(icon: "square.and.arrow.up",
                           title: "画像・動画に書き出す",
                           detail: "ポスターやループ動画にして残せます")
            }
            .padding(.top, 4)

            Spacer(minLength: 8)

            Button {
                Haptics.success()
                onFinish()
            } label: {
                Text("はじめる")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [AppTheme.coral, AppTheme.sunset],
                                       startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                    .shadow(color: AppTheme.coral.opacity(0.5), radius: 12, y: 6)
            }

            Text("この夏の一日を、閉じ込めにいきましょう。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - 瓶のイラスト(SwiftUI図形)

/// グラデ空+海+砂+瓶シルエット。ゆっくり左右に揺れる。
private struct OnboardingBottleIllustration: View {
    @State private var swaying = false

    var body: some View {
        ZStack(alignment: .top) {
            // コルク栓
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(colors: [AppTheme.shelfWood, Color(hex: "#8A6A4B")],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 48, height: 30)

            // 瓶本体(中身をシルエットでクリップ)
            bottleBody
                .frame(width: 170, height: 240)
                .padding(.top, 18)
        }
        .rotationEffect(.degrees(swaying ? 2.5 : -2.5), anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                swaying = true
            }
        }
    }

    private var bottleBody: some View {
        ZStack {
            // 空のグラデーション
            AppTheme.skyGradient(for: .daytime)

            // 太陽
            Circle()
                .fill(Color(hex: "#FFE08A"))
                .frame(width: 34, height: 34)
                .offset(x: 44, y: -58)
                .blur(radius: 1)

            // 入道雲
            HStack(spacing: -10) {
                Circle().frame(width: 26, height: 26)
                Circle().frame(width: 36, height: 36).offset(y: -6)
                Circle().frame(width: 24, height: 24)
            }
            .foregroundStyle(.white.opacity(0.9))
            .offset(x: -34, y: -34)

            // 海(ゆらゆら逆方向にオフセット)
            OnboardingWaveShape()
                .fill(
                    LinearGradient(colors: [AppTheme.ocean, AppTheme.deepSea],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(height: 96)
                .offset(x: swaying ? 5 : -5, y: 52)

            // 砂浜
            OnboardingWaveShape()
                .fill(AppTheme.sand)
                .frame(height: 44)
                .offset(x: swaying ? -4 : 4, y: 98)

            // ガラスのハイライト
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 12, height: 120)
                .rotationEffect(.degrees(4))
                .offset(x: -54, y: -20)
        }
        .clipShape(OnboardingBottleShape())
        .overlay(
            OnboardingBottleShape()
                .fill(AppTheme.glassTint.opacity(0.12))
        )
        .overlay(
            OnboardingBottleShape()
                .stroke(.white.opacity(0.75), lineWidth: 2.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
    }
}

/// 首付きの瓶シルエット
private struct OnboardingBottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let neckWidth = w * 0.34
        let neckLeft = rect.midX - neckWidth / 2
        let neckRight = rect.midX + neckWidth / 2
        let neckBottom = rect.minY + h * 0.15
        let shoulderY = rect.minY + h * 0.32
        let corner = w * 0.14

        var path = Path()
        path.move(to: CGPoint(x: neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: neckBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: shoulderY),
            control: CGPoint(x: rect.maxX, y: neckBottom)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - corner),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: neckLeft, y: neckBottom),
            control: CGPoint(x: rect.minX, y: neckBottom)
        )
        path.closeSubpath()
        return path
    }
}

/// 上端が波打つ帯(海・砂に使用)
private struct OnboardingWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let crestY = rect.minY + rect.height * 0.28
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: crestY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: crestY),
            control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: crestY),
            control: CGPoint(x: rect.minX + rect.width * 0.75, y: crestY + rect.height * 0.35)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
