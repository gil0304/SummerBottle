//
//  PreviewStep.swift
//  SummerBottle
//
//  作成フロー ステップ4: プレビュー。
//  BottlePreview3DView を大きく表示し、「作り直す」(SceneComposer再実行)、
//  「編集する」(SceneEditView をシートで表示)、「保存する」(onSave)を提供する。
//

import CoreGraphics
import SwiftUI

/// 作成フロー ステップ4: 3Dプレビューと保存。
struct PreviewStep: View {
    let draft: BottleDraft
    let onBack: () -> Void
    let onSave: () -> Void

    init(draft: BottleDraft, onBack: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.draft = draft
        self.onBack = onBack
        self.onSave = onSave
    }

    @State private var photoImages: [UUID: CGImage] = [:]
    @State private var isLoadingImages = true
    @State private var showEditor = false

    private var configBinding: Binding<SceneConfig> {
        Binding(
            get: { draft.sceneConfig ?? SceneConfig() },
            set: { draft.sceneConfig = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlBar

            CreateStepFooter(
                nextTitle: "保存する",
                nextEnabled: draft.sceneConfig != nil,
                onBack: onBack,
                onNext: onSave
            )
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                SceneEditView(config: configBinding, photos: photoImages)
                    .navigationTitle("シーンを編集")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完了") {
                                showEditor = false
                            }
                        }
                    }
            }
        }
        .task {
            if draft.sceneConfig == nil {
                draft.sceneConfig = SceneComposer.compose(draft: draft)
            }
            await loadImages()
        }
    }

    // MARK: - プレビュー

    @ViewBuilder
    private var previewArea: some View {
        if let config = draft.sceneConfig, !isLoadingImages {
            VStack(spacing: 8) {
                BottlePreview3DView(config: config, photos: photoImages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 3) {
                    Text(config.bottleType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !config.labelText.isEmpty {
                        Text(config.labelText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    Text("ドラッグで回転・ピンチで拡大できます")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("ボトルを準備しています…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 操作ボタン

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                regenerate()
            } label: {
                Label("作り直す", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ocean)

            Button {
                Haptics.tap()
                showEditor = true
            } label: {
                Label("編集する", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ocean)
        }
        .controlSize(.regular)
        .disabled(draft.sceneConfig == nil || isLoadingImages)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func regenerate() {
        Haptics.medium()
        withAnimation(.easeInOut(duration: 0.25)) {
            draft.sceneConfig = SceneComposer.compose(draft: draft)
        }
    }

    // MARK: - 写真の読み込み

    private func loadImages() async {
        let sources = draft.photos.map { ($0.id, $0.data) }
        let images = await Task.detached(priority: .userInitiated) { () -> [UUID: CGImage] in
            var result: [UUID: CGImage] = [:]
            for (id, data) in sources {
                if let cgImage = ImageUtil.cgImage(from: data, maxPixel: 1024) {
                    result[id] = cgImage
                }
            }
            return result
        }.value
        photoImages = images
        isLoadingImages = false
    }
}
