//
//  ExportView.swift
//  SummerBottle
//
//  書き出し画面。形式選択カード+3Dプレビュー+進捗表示+
//  完了後の共有(ShareLink)・写真への保存を提供する。
//

import SwiftUI
import UIKit
import AVKit

struct ExportView: View {
    private let bottleID: Bottle.ID

    init(bottleID: Bottle.ID) {
        self.bottleID = bottleID
    }

    @Environment(BottleStore.self) private var store

    @State private var selectedFormat: ExportFormat = .square
    @State private var phase: Phase = .idle
    @State private var videoProgress: Double = 0
    @State private var resultImages: [UIImage] = []
    @State private var shareURLs: [URL] = []
    @State private var resultVideoURL: URL?
    @State private var videoPlayer: AVPlayer?
    @State private var previewPhotos: [UUID: CGImage] = [:]
    @State private var didLoadPreviewPhotos = false
    @State private var showSavedAlert = false

    // MARK: - 内部型

    private enum Phase: Equatable {
        case idle
        case working
        case done
        case failed
    }

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case square
        case portrait
        case landscape
        case transparent
        case poster
        case video
        case postcard

        var id: String { rawValue }

        var title: String {
            switch self {
            case .square: "正方形"
            case .portrait: "9:16"
            case .landscape: "16:9"
            case .transparent: "透過背景"
            case .poster: "ポスター"
            case .video: "ループ動画"
            case .postcard: "ポストカード"
            }
        }

        var subtitle: String {
            switch self {
            case .square: "1080×1080・SNS投稿に"
            case .portrait: "1080×1920・ストーリーズに"
            case .landscape: "1920×1080・共有に"
            case .transparent: "背景なしPNG・ステッカー風"
            case .poster: "日付と一言入りの縦長1枚"
            case .video: "8秒・1080×1920・30fps"
            case .postcard: "表・裏の2枚組"
            }
        }

        var symbol: String {
            switch self {
            case .square: "square"
            case .portrait: "rectangle.portrait"
            case .landscape: "rectangle"
            case .transparent: "checkerboard.rectangle"
            case .poster: "doc.richtext"
            case .video: "video.fill"
            case .postcard: "envelope.open"
            }
        }
    }

    // MARK: - 本体

    var body: some View {
        Group {
            if let bottle = store.bottle(id: bottleID) {
                exportContent(bottle: bottle)
            } else {
                ContentUnavailableView("ボトルが見つかりません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .alert("写真に保存しました", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func exportContent(bottle: Bottle) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                previewSection(bottle: bottle)
                formatGrid
                actionSection(bottle: bottle)
                if phase == .done {
                    resultSection
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            if !didLoadPreviewPhotos {
                didLoadPreviewPhotos = true
                previewPhotos = store.photoCGImages(for: bottle)
            }
        }
    }

    // MARK: - プレビュー

    private func previewSection(bottle: Bottle) -> some View {
        VStack(spacing: 8) {
            BottlePreview3DView(config: bottle.sceneConfig, photos: previewPhotos)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .background(AppTheme.skyGradient(for: bottle.timeOfDay))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text(bottle.title)
                .font(.subheadline.weight(.semibold))
            Text(bottle.memoryDate.japaneseDateString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 形式選択

    private var formatGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("書き出し形式")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    formatCard(format)
                }
            }
        }
    }

    private func formatCard(_ format: ExportFormat) -> some View {
        let isSelected = selectedFormat == format
        return Button {
            guard phase != .working else { return }
            selectedFormat = format
            resetResult()
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: format.symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.ocean : .secondary)
                Text(format.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(format.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppTheme.ocean.opacity(0.14) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? AppTheme.ocean : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 実行と進捗

    @ViewBuilder
    private func actionSection(bottle: Bottle) -> some View {
        if phase == .working {
            VStack(spacing: 12) {
                if selectedFormat == .video {
                    ProgressView(value: videoProgress) {
                        Text("動画を書き出し中…")
                            .font(.subheadline)
                    } currentValueLabel: {
                        Text("\(Int(videoProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tint(AppTheme.ocean)
                } else {
                    ProgressView("書き出し中…")
                        .tint(AppTheme.ocean)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        } else {
            VStack(spacing: 10) {
                Button {
                    startExport(bottle: bottle)
                } label: {
                    Label("書き出す", systemImage: "square.and.arrow.up.on.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ocean)

                if phase == .failed {
                    Label("書き出しに失敗しました。もう一度お試しください。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func startExport(bottle: Bottle) {
        guard phase != .working else { return }
        resetResult()
        phase = .working
        Haptics.medium()
        Task {
            await performExport(bottle: bottle)
        }
    }

    private func resetResult() {
        phase = .idle
        videoProgress = 0
        resultImages = []
        shareURLs = []
        resultVideoURL = nil
        videoPlayer = nil
    }

    private func performExport(bottle: Bottle) async {
        let photos = store.photoCGImages(for: bottle)
        let renderer = ExportRenderer()

        switch selectedFormat {
        case .square:
            let image = await renderer.renderStill(
                bottle: bottle, photos: photos,
                size: CGSize(width: 1080, height: 1080), transparent: false
            )
            finishImageExport(images: [image], asPNG: false, nameHint: "square")

        case .portrait:
            let image = await renderer.renderStill(
                bottle: bottle, photos: photos,
                size: CGSize(width: 1080, height: 1920), transparent: false
            )
            finishImageExport(images: [image], asPNG: false, nameHint: "story")

        case .landscape:
            let image = await renderer.renderStill(
                bottle: bottle, photos: photos,
                size: CGSize(width: 1920, height: 1080), transparent: false
            )
            finishImageExport(images: [image], asPNG: false, nameHint: "wide")

        case .transparent:
            let image = await renderer.renderStill(
                bottle: bottle, photos: photos,
                size: CGSize(width: 1080, height: 1350), transparent: true
            )
            finishImageExport(images: [image], asPNG: true, nameHint: "clear")

        case .poster:
            let image = await renderer.renderPoster(bottle: bottle, photos: photos)
            finishImageExport(images: [image], asPNG: false, nameHint: "poster")

        case .postcard:
            if let pair = await renderer.renderPostcard(bottle: bottle, photos: photos) {
                finishImageExport(images: [pair.front, pair.back], asPNG: false, nameHint: "postcard")
            } else {
                phase = .failed
            }

        case .video:
            let url = await renderer.renderLoopVideo(
                bottle: bottle, photos: photos, duration: 8,
                progress: { value in
                    videoProgress = value
                }
            )
            if let url {
                resultVideoURL = url
                shareURLs = [url]
                videoPlayer = AVPlayer(url: url)
                phase = .done
                Haptics.success()
            } else {
                phase = .failed
            }
        }
    }

    /// 画像結果を一時ファイルへ書き出して共有可能にする
    private func finishImageExport(images: [UIImage?], asPNG: Bool, nameHint: String) {
        let valid = images.compactMap { $0 }
        guard !valid.isEmpty, valid.count == images.count else {
            phase = .failed
            return
        }
        var urls: [URL] = []
        let stamp = Int(Date().timeIntervalSince1970)
        for (index, image) in valid.enumerated() {
            let ext = asPNG ? "png" : "jpg"
            guard let data = asPNG ? image.pngData() : image.jpegData(compressionQuality: 0.92) else {
                phase = .failed
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SummerBottle_\(nameHint)_\(stamp)_\(index + 1).\(ext)")
            do {
                try data.write(to: url, options: .atomic)
                urls.append(url)
            } catch {
                phase = .failed
                return
            }
        }
        resultImages = valid
        shareURLs = urls
        phase = .done
        Haptics.success()
    }

    // MARK: - 結果表示

    private var resultSection: some View {
        VStack(spacing: 14) {
            Label("書き出しが完了しました", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.ocean)

            if let player = videoPlayer {
                VideoPlayer(player: player)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if selectedFormat == .postcard, resultImages.count == 2 {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 6) {
                        resultImageView(resultImages[0])
                        Text("表")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        resultImageView(resultImages[1])
                        Text("裏")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let image = resultImages.first {
                resultImageView(image)
                    .frame(maxHeight: 360)
            }

            HStack(spacing: 12) {
                ShareLink(items: shareURLs) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.ocean)

                Button {
                    saveToPhotos()
                } label: {
                    Label("写真に保存", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ocean)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func resultImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - 写真への保存

    private func saveToPhotos() {
        if let videoURL = resultVideoURL {
            UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
        } else {
            for image in resultImages {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
        showSavedAlert = true
        Haptics.success()
    }
}
