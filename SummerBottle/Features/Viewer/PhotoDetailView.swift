//
//  PhotoDetailView.swift
//  SummerBottle
//
//  フォトカードをタップしたときの全画面写真表示。
//  ピンチズーム(1〜4倍)+ドラッグパン、ダブルタップでリセット。
//

import SwiftUI
import UIKit

struct PhotoDetailView: View {
    @Environment(BottleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let bottleID: Bottle.ID
    private let photoID: UUID

    init(bottleID: Bottle.ID, photoID: UUID) {
        self.bottleID = bottleID
        self.photoID = photoID
    }

    @State private var image: UIImage?
    @State private var loadFinished = false

    // ズーム・パン
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var basePanOffset: CGSize = .zero

    /// 対象写真とその表示順(何枚目/全何枚)
    private var photoInfo: (photo: BottlePhoto, index: Int, total: Int)? {
        guard let bottle = store.bottle(id: bottleID) else { return nil }
        let sorted = bottle.photos.sorted { $0.displayOrder < $1.displayOrder }
        guard let index = sorted.firstIndex(where: { $0.id == photoID }) else { return nil }
        return (sorted[index], index + 1, sorted.count)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                imageView(image)
            } else if loadFinished {
                ContentUnavailableView(
                    "写真を読み込めませんでした",
                    systemImage: "photo",
                    description: Text("ファイルが見つからないか、破損している可能性があります。")
                )
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                Spacer()
                metaBar
                    .allowsHitTesting(false)
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadImage)
    }

    // MARK: - 画像表示

    private func imageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(zoom)
            .offset(panOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(magnifyGesture.simultaneously(with: panGesture))
            .onTapGesture(count: 2) {
                resetZoom()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(4, max(1, baseZoom * value.magnification))
            }
            .onEnded { _ in
                baseZoom = zoom
                if zoom <= 1 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        panOffset = .zero
                        basePanOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                panOffset = CGSize(
                    width: basePanOffset.width + value.translation.width,
                    height: basePanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                basePanOffset = panOffset
            }
    }

    private func resetZoom() {
        withAnimation(.spring(duration: 0.3)) {
            zoom = 1
            baseZoom = 1
            panOffset = .zero
            basePanOffset = .zero
        }
    }

    // MARK: - 上下のUI

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(11)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("閉じる")
    }

    private var metaBar: some View {
        VStack(spacing: 10) {
            if let info = photoInfo {
                Text("\(info.index)枚目 / 全\(info.total)枚")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                if let analysis = info.photo.analysis, !analysis.elements.isEmpty {
                    elementChips(analysis)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func elementChips(_ analysis: PhotoAnalysis) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(analysis.elements.sorted { $0.rawValue < $1.rawValue }, id: \.self) { element in
                    Text(element.displayName)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - 読み込み

    private func loadImage() {
        guard image == nil else { return }
        defer { loadFinished = true }
        guard let info = photoInfo,
              let data = store.photoData(bottleID: bottleID, fileName: info.photo.fileName)
        else { return }
        image = UIImage(data: data)
    }
}
