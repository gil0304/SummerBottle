//
//  AnalyzeStep.swift
//  SummerBottle
//
//  作成フロー ステップ3: 自動解析。
//  各写真に PhotoAnalyzer.analyze を順次実行(進捗 x/N を表示)し、
//  完了後 SceneComposer.compose で draft.sceneConfig を作る。
//  揺れる瓶のアニメーション演出を最低1.2秒は見せてから自動で完了する。
//

import SwiftUI

/// 作成フロー ステップ3: 写真の自動解析とシーン構成。
struct AnalyzeStep: View {
    let draft: BottleDraft
    let onFinished: () -> Void

    init(draft: BottleDraft, onFinished: @escaping () -> Void) {
        self.draft = draft
        self.onFinished = onFinished
    }

    private enum AnalyzePhase {
        case analyzing
        case composing
        case done
    }

    @State private var hasStarted = false
    @State private var phase: AnalyzePhase = .analyzing
    @State private var doneCount = 0

    private var totalCount: Int {
        max(draft.photos.count, 1)
    }

    private var statusText: String {
        switch phase {
        case .analyzing:
            return "写真を解析しています(\(min(doneCount + 1, draft.photos.count))/\(draft.photos.count))"
        case .composing:
            return "ボトルの中の風景を組み立てています…"
        case .done:
            return "できあがり!"
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            AnalyzeBottleArt()

            VStack(spacing: 12) {
                Text(statusText)
                    .font(.headline)
                    .contentTransition(.numericText())
                ProgressView(value: progressValue)
                    .tint(AppTheme.ocean)
                    .frame(maxWidth: 240)
                Text("写真から夏の要素を見つけて、\nミニチュアと空の色を選んでいます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
    }

    private var progressValue: Double {
        switch phase {
        case .analyzing:
            return Double(doneCount) / Double(totalCount + 1)
        case .composing:
            return Double(totalCount) / Double(totalCount + 1)
        case .done:
            return 1
        }
    }

    // MARK: - 解析の実行

    private func run() async {
        let start = ContinuousClock.now

        phase = .analyzing
        for index in draft.photos.indices {
            if draft.photos[index].analysis == nil {
                let data = draft.photos[index].data
                let result = await PhotoAnalyzer.analyze(imageData: data)
                if Task.isCancelled { return }
                if draft.photos.indices.contains(index) {
                    draft.photos[index].analysis = result
                }
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                doneCount = index + 1
            }
        }

        phase = .composing
        draft.sceneConfig = SceneComposer.compose(draft: draft)

        // 演出を最低1.2秒は見せる
        let minimum = Duration.seconds(1.2)
        let elapsed = start.duration(to: .now)
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
        }
        if Task.isCancelled { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            phase = .done
        }
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        onFinished()
    }
}

// MARK: - 揺れる瓶の演出

fileprivate struct AnalyzeBottleArt: View {
    @State private var swing: Double = -6
    @State private var waterRise: CGFloat = 0
    @State private var sparklePulse = false

    var body: some View {
        ZStack {
            // きらめき
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(AppTheme.sunset)
                .offset(x: -78, y: -70)
                .opacity(sparklePulse ? 1 : 0.25)
                .scaleEffect(sparklePulse ? 1.15 : 0.8)
            Image(systemName: "sparkle")
                .font(.title3)
                .foregroundStyle(AppTheme.coral)
                .offset(x: 82, y: -34)
                .opacity(sparklePulse ? 0.3 : 1)
                .scaleEffect(sparklePulse ? 0.8 : 1.1)
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(AppTheme.ocean)
                .offset(x: 66, y: 74)
                .opacity(sparklePulse ? 1 : 0.3)

            // 瓶
            VStack(spacing: -6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#C58B5A"))
                    .frame(width: 30, height: 22)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 34)
                        .fill(AppTheme.glassTint.opacity(0.45))
                        .frame(width: 118, height: 186)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.ocean.opacity(0.85), AppTheme.deepSea.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 102, height: 78 + waterRise)
                        .padding(.bottom, 8)
                    RoundedRectangle(cornerRadius: 34)
                        .strokeBorder(AppTheme.ocean.opacity(0.5), lineWidth: 3)
                        .frame(width: 118, height: 186)
                }
            }
            .rotationEffect(.degrees(swing), anchor: .bottom)
        }
        .frame(height: 240)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                swing = 6
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                waterRise = 34
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                sparklePulse = true
            }
        }
        .accessibilityLabel("解析中の演出")
    }
}
