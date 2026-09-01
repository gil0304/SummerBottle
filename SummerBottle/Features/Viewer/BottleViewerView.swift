//
//  BottleViewerView.swift
//  SummerBottle
//
//  3D鑑賞画面。RealityView + BottleSceneController で瓶の中の夏を眺める。
//  ドラッグで回転、ピンチでズーム、上部で上スワイプすると栓が開いて音が流れる。
//

import SwiftUI
import RealityKit
import simd

struct BottleViewerView: View {
    @Environment(BottleStore.self) private var store

    private let bottleID: Bottle.ID

    init(bottleID: Bottle.ID) {
        self.bottleID = bottleID
    }

    var body: some View {
        if let bottle = store.bottle(id: bottleID) {
            ViewerSceneScreen(bottle: bottle)
        } else {
            ContentUnavailableView(
                "ボトルが見つかりません",
                systemImage: "questionmark.circle",
                description: Text("このボトルは削除された可能性があります。")
            )
            .navigationTitle("鑑賞")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 内部画面(ボトルが存在するとき)

private struct ViewerSceneScreen: View {
    let bottle: Bottle

    @Environment(BottleStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    // 3D
    @State private var controller: BottleSceneController?
    @State private var cameraEntity: PerspectiveCamera?
    @State private var motion = MotionManager()

    // 回転(Y軸ヨー+わずかなX傾き)
    @State private var yaw: Float = 0
    @State private var tilt: Float = 0
    @State private var dragMode: ViewerDragMode?
    @State private var dragBaseYaw: Float = 0
    @State private var dragBaseTilt: Float = 0

    // ズーム(カメラ距離の倍率 0.5〜2.5)
    @State private var zoom: Float = 1
    @State private var baseZoom: Float = 1

    // 栓・オーバーレイ
    @State private var isCorkOpen = false
    @State private var showComment = false
    @State private var commentHideTask: Task<Void, Never>?

    // シート・ダイアログ
    @State private var selectedPhoto: ViewerSelectedPhoto?
    @State private var showDeleteConfirm = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.skyGradient(for: bottle.timeOfDay)
                    .ignoresSafeArea()

                realityLayer(viewHeight: geometry.size.height)

                overlayLayer
            }
        }
        .navigationTitle(bottle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "このボトルを削除しますか?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("写真と音声も含めて完全に削除されます。この操作は取り消せません。")
        }
        .fullScreenCover(item: $selectedPhoto) { selection in
            PhotoDetailView(bottleID: bottle.id, photoID: selection.id)
        }
        .onAppear {
            motion.start()
        }
        .onDisappear {
            motion.stop()
            commentHideTask?.cancel()
            if isCorkOpen {
                closeCork()
            } else {
                AudioService.shared.stop()
            }
        }
        .onChange(of: bottle.updatedAt) { _, _ in
            // 編集から戻ってきたときにシーンを作り直す
            guard let controller else { return }
            controller.update(config: bottle.sceneConfig, photos: store.photoCGImages(for: bottle))
            positionCamera()
        }
    }

    // MARK: - RealityView

    private func realityLayer(viewHeight: CGFloat) -> some View {
        RealityView { content in
            let ctrl = BottleSceneController(
                config: bottle.sceneConfig,
                photos: store.photoCGImages(for: bottle)
            )
            content.add(ctrl.rootEntity)

            let camera = PerspectiveCamera()
            content.add(camera)
            let height = ctrl.bottleHeight
            camera.look(
                at: SIMD3<Float>(0, height * 0.5, 0),
                from: SIMD3<Float>(0, height * 0.65, height * 2.4),
                relativeTo: nil
            )

            controller = ctrl
            cameraEntity = camera

            // モーション連動
            motion.onUpdate = { pitch, roll in
                ctrl.applyTilt(pitch: pitch, roll: roll)
            }
            motion.onShake = {
                Haptics.medium()
                ctrl.triggerShake()
            }
            motion.start()
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let photoID = controller?.photoID(for: value.entity) {
                        Haptics.tap()
                        selectedPhoto = ViewerSelectedPhoto(id: photoID)
                    }
                }
        )
        .simultaneousGesture(dragGesture(viewHeight: viewHeight))
        .simultaneousGesture(magnifyGesture)
    }

    // MARK: - ジェスチャ

    private func dragGesture(viewHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragMode == nil {
                    // 最初の移動方向と開始位置でモードを決める
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if value.startLocation.y < viewHeight / 3, dy > dx {
                        dragMode = .cork
                    } else {
                        dragMode = .rotate
                        dragBaseYaw = yaw
                        dragBaseTilt = tilt
                    }
                }
                guard dragMode == .rotate else { return }
                yaw = dragBaseYaw + Float(value.translation.width) * 0.012
                tilt = max(-0.3, min(0.3, dragBaseTilt + Float(value.translation.height) * 0.006))
                applyBottleRotation()
            }
            .onEnded { value in
                if dragMode == .cork {
                    if value.translation.height < -40 {
                        // 上スワイプ: 開閉トグル
                        if isCorkOpen {
                            closeCork()
                        } else {
                            openCork()
                        }
                    } else if value.translation.height > 40, isCorkOpen {
                        // 下スワイプ: 閉栓
                        closeCork()
                    }
                }
                dragMode = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let magnification = Float(value.magnification)
                guard magnification > 0 else { return }
                // ピンチアウト(拡大)でカメラが近づく
                zoom = max(0.5, min(2.5, baseZoom / magnification))
                positionCamera()
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }

    private func applyBottleRotation() {
        guard let controller else { return }
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let tiltRotation = simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0))
        controller.rootEntity.orientation = tiltRotation * yawRotation
    }

    private func positionCamera() {
        guard let controller, let cameraEntity else { return }
        let height = controller.bottleHeight
        let distance = height * 2.4 * zoom
        cameraEntity.look(
            at: SIMD3<Float>(0, height * 0.5, 0),
            from: SIMD3<Float>(0, height * 0.65, distance),
            relativeTo: nil
        )
    }

    // MARK: - 栓の開閉

    private func openCork() {
        guard let controller else { return }
        controller.setCorkOpen(true)
        withAnimation(.easeOut(duration: 0.35)) { isCorkOpen = true }
        Haptics.medium()

        // 録音があればそれを、なければプリセット環境音を再生
        if let url = store.audioURL(for: bottle),
           FileManager.default.fileExists(atPath: url.path) {
            AudioService.shared.playFile(at: url, loop: true)
        } else {
            AudioService.shared.playPreset(bottle.sceneConfig.soundscape, loop: true)
        }

        // 一言を数秒だけふわっと表示
        if let comment = bottle.comment, !comment.isEmpty {
            commentHideTask?.cancel()
            withAnimation(.easeOut(duration: 0.5)) { showComment = true }
            commentHideTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.6)) { showComment = false }
            }
        }
    }

    private func closeCork() {
        controller?.setCorkOpen(false)
        withAnimation(.easeIn(duration: 0.3)) {
            isCorkOpen = false
            showComment = false
        }
        commentHideTask?.cancel()
        AudioService.shared.stop()
        Haptics.tap()
    }

    private func performDelete() {
        AudioService.shared.stop()
        motion.stop()
        store.delete(bottle.id)
        dismiss()
    }

    // MARK: - オーバーレイ

    private var overlayLayer: some View {
        VStack(spacing: 16) {
            if isCorkOpen {
                corkOpenIndicator
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            if showComment, let comment = bottle.comment, !comment.isEmpty {
                commentCard(comment)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }

            Spacer()

            if !isCorkOpen {
                swipeHint
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: isCorkOpen)
    }

    private var corkOpenIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.footnote)
                .foregroundStyle(AppTheme.coral)
            Text("栓が開いています")
                .font(.footnote)
            Button("閉じる") {
                closeCork()
            }
            .font(.footnote.bold())
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func commentCard(_ comment: String) -> some View {
        VStack(spacing: 8) {
            Text(bottle.memoryDate.japaneseDateString)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(comment)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 24)
    }

    private var swipeHint: some View {
        Label("上にスワイプで栓を開ける", systemImage: "chevron.up")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.tap()
                store.toggleFavorite(bottle.id)
            } label: {
                Image(systemName: bottle.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(bottle.isFavorite ? AppTheme.coral : Color.primary)
            }
            .accessibilityLabel(bottle.isFavorite ? "お気に入りを解除" : "お気に入りに追加")
        }

        if !motion.isAvailable {
            // シミュレータなどモーション非対応時の代替ボタン
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.medium()
                    controller?.triggerShake()
                } label: {
                    Label("ゆらす", systemImage: "sparkles")
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    router.open(.edit(bottle.id))
                } label: {
                    Label("編集", systemImage: "slider.horizontal.3")
                }
                Button {
                    router.open(.export(bottle.id))
                } label: {
                    Label("書き出し", systemImage: "square.and.arrow.up")
                }
                Button {
                    router.open(.ar(bottle.id))
                } label: {
                    Label("ARで表示", systemImage: "arkit")
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - 補助型(このファイル内のみ)

private enum ViewerDragMode {
    case rotate
    case cork
}

private struct ViewerSelectedPhoto: Identifiable {
    let id: UUID
}
