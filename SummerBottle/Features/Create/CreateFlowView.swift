//
//  CreateFlowView.swift
//  SummerBottle
//
//  作成フローの親ビュー。写真選択→基本情報→自動解析→プレビュー→保存の
//  ステップを管理し、保存時に BottleStore へ追加する。
//

import SwiftUI

// MARK: - ステップ定義

fileprivate enum CreateFlowStep: Int, CaseIterable {
    case photos
    case info
    case analyze
    case preview

    var title: String {
        switch self {
        case .photos: "写真を選ぶ"
        case .info: "基本情報"
        case .analyze: "自動解析"
        case .preview: "プレビュー"
        }
    }

    var shortLabel: String {
        switch self {
        case .photos: "写真"
        case .info: "情報"
        case .analyze: "解析"
        case .preview: "確認"
        }
    }
}

// MARK: - 作成フロー

/// 全画面の作成フロー。BottleDraft を内部で生成し、ステップを進める。
/// 保存時は BottleStore.add(...) → dismiss。
struct CreateFlowView: View {
    @Environment(BottleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = BottleDraft()
    @State private var step: CreateFlowStep = .photos
    @State private var showCloseConfirm = false

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CreateProgressHeader(current: step)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                Divider()
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if hasEnteredContent {
                            showCloseConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("閉じる")
                }
            }
            .confirmationDialog(
                "作成をやめますか?",
                isPresented: $showCloseConfirm,
                titleVisibility: .visible
            ) {
                Button("やめて閉じる", role: .destructive) {
                    dismiss()
                }
                Button("作成を続ける", role: .cancel) {}
            } message: {
                Text("入力した内容と選んだ写真は保存されません。")
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .photos:
            PhotoPickStep(draft: draft) {
                advance(to: .info)
            }
        case .info:
            InfoStep(
                draft: draft,
                onBack: { advance(to: .photos) },
                onNext: { advance(to: .analyze) }
            )
        case .analyze:
            AnalyzeStep(draft: draft) {
                advance(to: .preview)
            }
        case .preview:
            PreviewStep(
                draft: draft,
                onBack: { advance(to: .info) },
                onSave: { save() }
            )
        }
    }

    private var hasEnteredContent: Bool {
        !draft.photos.isEmpty
            || !draft.title.isEmpty
            || !draft.comment.isEmpty
            || draft.recordedAudioURL != nil
    }

    private func advance(to newStep: CreateFlowStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = newStep
        }
    }

    // MARK: - 保存

    private func save() {
        let config = draft.sceneConfig ?? SceneComposer.compose(draft: draft)

        var photos: [BottlePhoto] = []
        var photoDatas: [UUID: Data] = [:]
        for (index, draftPhoto) in draft.photos.enumerated() {
            photos.append(BottlePhoto(
                id: draftPhoto.id,
                fileName: "\(draftPhoto.id).jpg",
                displayOrder: index,
                analysis: draftPhoto.analysis
            ))
            photoDatas[draftPhoto.id] = draftPhoto.data
        }

        let audio: BottleAudio
        if draft.recordedAudioURL != nil {
            audio = BottleAudio(
                fileName: "voice.m4a",
                duration: draft.recordedDuration,
                type: .recorded,
                preset: nil,
                containsVoice: draft.recordedContainsVoice
            )
        } else {
            audio = BottleAudio(
                fileName: nil,
                duration: 0,
                type: .preset,
                preset: config.soundscape,
                containsVoice: false
            )
        }

        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = draft.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)

        let bottle = Bottle(
            title: trimmedTitle.isEmpty ? "夏の一日" : trimmedTitle,
            memoryDate: draft.memoryDate,
            locationName: trimmedLocation.isEmpty ? nil : trimmedLocation,
            latitude: draft.latitude,
            longitude: draft.longitude,
            memoryType: draft.memoryType,
            comment: trimmedComment.isEmpty ? nil : trimmedComment,
            companions: draft.companions,
            sceneConfig: config,
            photos: photos,
            audio: audio
        )

        store.add(bottle, photoDatas: photoDatas, audioSourceURL: draft.recordedAudioURL)
        Haptics.success()
        dismiss()
    }
}

// MARK: - 進捗インジケータ

fileprivate struct CreateProgressHeader: View {
    let current: CreateFlowStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CreateFlowStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(step.rawValue <= current.rawValue
                              ? AppTheme.ocean
                              : Color(uiColor: .systemFill))
                        .frame(height: 4)
                    Text(step.shortLabel)
                        .font(.caption2)
                        .fontWeight(step == current ? .semibold : .regular)
                        .foregroundStyle(step == current ? AppTheme.ocean : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ステップ \(current.rawValue + 1) / \(CreateFlowStep.allCases.count): \(current.title)")
    }
}

// MARK: - ステップ共通フッター(作成フロー専用の共有部品)

struct CreateStepFooter: View {
    var backTitle: String? = "戻る"
    let nextTitle: String
    var nextEnabled: Bool = true
    var onBack: (() -> Void)? = nil
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    Text(backTitle ?? "戻る")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.bordered)
            }
            Button {
                Haptics.tap()
                onNext()
            } label: {
                Text(nextTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ocean)
            .disabled(!nextEnabled)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - 横スクロールチップ(作成フロー専用の共有部品)

struct CreateChipRow<Item: Identifiable>: View {
    let items: [Item]
    var selectedID: Item.ID?
    let title: (Item) -> String
    var symbol: ((Item) -> String)? = nil
    let onTap: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    chip(for: item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(for item: Item) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            onTap(item)
        } label: {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol(item))
                        .font(.caption)
                }
                Text(title(item))
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? AppTheme.ocean : Color(uiColor: .secondarySystemFill),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
