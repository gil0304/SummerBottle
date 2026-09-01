//
//  PhotoPickStep.swift
//  SummerBottle
//
//  作成フロー ステップ1: 写真選択。
//  PhotosPicker(最大10枚)で選んだ写真を ImageUtil.downscaledJPEGData で縮小して
//  draft.photos へ追加する。グリッドプレビュー・削除・左右ボタンでの並べ替えに対応。
//  1枚以上選ぶと「次へ」が有効になる。
//

import PhotosUI
import SwiftUI
import UIKit

/// 作成フロー ステップ1: 写真選択(1〜10枚)。
struct PhotoPickStep: View {
    let draft: BottleDraft
    let onNext: () -> Void

    init(draft: BottleDraft, onNext: @escaping () -> Void) {
        self.draft = draft
        self.onNext = onNext
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoading = false

    private let maxPhotoCount = 10
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("この日の写真を1〜10枚選んでください。\n1枚目がボトルの正面に飾られます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoPickCell(
                                photo: photo,
                                index: index,
                                isFirst: index == 0,
                                isLast: index == draft.photos.count - 1,
                                onMoveBack: { movePhoto(at: index, offset: -1) },
                                onMoveForward: { movePhoto(at: index, offset: 1) },
                                onDelete: { deletePhoto(photo.id) }
                            )
                        }
                        if draft.photos.count < maxPhotoCount {
                            addTile
                        }
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("写真を読み込んでいます…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }

                    if !draft.photos.isEmpty {
                        Text("矢印ボタンで順番を入れ替えられます(\(draft.photos.count)/\(maxPhotoCount)枚)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            CreateStepFooter(
                nextTitle: "次へ",
                nextEnabled: !draft.photos.isEmpty && !isLoading,
                onNext: onNext
            )
        }
        .onChange(of: pickerItems) { _, newItems in
            loadSelection(newItems)
        }
    }

    // MARK: - 追加タイル

    private var addTile: some View {
        let tileTitle = draft.photos.isEmpty ? "写真を選ぶ" : "追加"
        return PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, maxPhotoCount - draft.photos.count),
            matching: .images
        ) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text(tileTitle)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.ocean)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.glassTint.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppTheme.ocean.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .disabled(isLoading)
    }

    // MARK: - 読み込み・並べ替え・削除

    private func loadSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoading = true
        Task {
            for item in items {
                guard draft.photos.count < maxPhotoCount else { break }
                let rawData = (try? await item.loadTransferable(type: Data.self)) ?? nil
                guard let rawData else { continue }
                let jpeg = await Task.detached(priority: .userInitiated) {
                    ImageUtil.downscaledJPEGData(from: rawData)
                }.value
                if let jpeg {
                    draft.photos.append(BottleDraft.DraftPhoto(data: jpeg))
                }
            }
            pickerItems = []
            isLoading = false
            if !draft.photos.isEmpty {
                Haptics.tap()
            }
        }
    }

    private func movePhoto(at index: Int, offset: Int) {
        let target = index + offset
        guard draft.photos.indices.contains(index),
              draft.photos.indices.contains(target)
        else { return }
        draft.photos.swapAt(index, target)
        Haptics.tap()
    }

    private func deletePhoto(_ id: UUID) {
        draft.photos.removeAll { $0.id == id }
        Haptics.tap()
    }
}

// MARK: - 写真セル

fileprivate struct PhotoPickCell: View {
    let photo: BottleDraft.DraftPhoto
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let onMoveBack: () -> Void
    let onMoveForward: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color(uiColor: .secondarySystemFill))
                        ProgressView()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                orderBadge
            }
            .overlay(alignment: .topTrailing) {
                deleteButton
            }
            .overlay(alignment: .bottom) {
                moveButtons
            }
            .task(id: photo.id) {
                if let cgImage = ImageUtil.cgImage(from: photo.data, maxPixel: 400) {
                    thumbnail = UIImage(cgImage: cgImage)
                }
            }
    }

    private var orderBadge: some View {
        Text(isFirst ? "1・正面" : "\(index + 1)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isFirst ? AppTheme.coral : Color.black.opacity(0.55), in: Capsule())
            .padding(6)
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(5)
        .accessibilityLabel("この写真を削除")
    }

    private var moveButtons: some View {
        HStack {
            Button {
                onMoveBack()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .opacity(isFirst ? 0.3 : 1)
            .accessibilityLabel("前へ移動")

            Spacer()

            Button {
                onMoveForward()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .opacity(isLast ? 0.3 : 1)
            .accessibilityLabel("後ろへ移動")
        }
        .padding(6)
    }
}
