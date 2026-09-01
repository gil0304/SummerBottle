//
//  ARBottleView.swift
//  SummerBottle
//
//  AR表示: 保存済みボトルを現実の床や机の上に置いて眺める。
//  - 平面検出+コーチングオーバーレイ、タップで配置
//  - 実物大/ミニチュアの切り替え(既存配置にも反映)
//  - 「ボトルを追加」で他の保存済みボトルも複数同時配置
//  - 写真撮影(snapshot→フォトライブラリ+共有)、動画撮影(ReplayKit)
//  - シミュレータ(ARWorldTrackingConfiguration.isSupported == false)では説明画面
//

import SwiftUI
import UIKit
import RealityKit
import ARKit
import ReplayKit

// MARK: - 公開ビュー(契約10章)

struct ARBottleView: View {
    @Environment(BottleStore.self) private var store
    @State private var model = ARBottlePlacementModel()

    private let bottleID: Bottle.ID

    init(bottleID: Bottle.ID) {
        self.bottleID = bottleID
    }

    var body: some View {
        Group {
            if ARWorldTrackingConfiguration.isSupported {
                supportedContent
            } else {
                ARUnsupportedNotice()
            }
        }
        .navigationTitle("ARで飾る")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.store = store
            if model.pendingBottleID == nil {
                model.pendingBottleID = bottleID
                if let bottle = store.bottle(id: bottleID) {
                    model.statusMessage = "床や机をゆっくり映して、タップで「\(bottle.title)」を置きます"
                }
            }
        }
        .onDisappear {
            model.tearDown()
        }
    }

    // MARK: 実機用コンテンツ

    private var supportedContent: some View {
        @Bindable var model = model
        return ZStack {
            ARBottleViewContainer(model: model)
                .ignoresSafeArea()

            VStack {
                topControls
                Spacer()
                bottomControls
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("次のタップで置くボトル") {
                        ForEach(store.bottles) { bottle in
                            Button {
                                model.pendingBottleID = bottle.id
                                model.statusMessage = "「\(bottle.title)」を選択中。平面をタップで配置します"
                            } label: {
                                if bottle.id == model.pendingBottleID {
                                    Label(bottle.title, systemImage: "checkmark")
                                } else {
                                    Text(bottle.title)
                                }
                            }
                        }
                    }
                } label: {
                    Label("ボトルを追加", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $model.showPhotoSheet) {
            if let image = model.capturedImage {
                ARPhotoResultSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(isPresented: $model.showVideoPreview) {
            if let preview = model.previewController {
                ARReplayPreviewHost(controller: preview) {
                    model.showVideoPreview = false
                    model.previewController = nil
                }
                .ignoresSafeArea()
            }
        }
        .alert("動画撮影", isPresented: $model.showRecordingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.recordingAlertMessage)
        }
        .onChange(of: model.isMiniature) {
            model.applyScaleToAll()
        }
    }

    // MARK: 上部コントロール(サイズ切替+ステータス)

    private var topControls: some View {
        @Bindable var model = model
        return VStack(spacing: 10) {
            Picker("大きさ", selection: $model.isMiniature) {
                Text("実物大").tag(false)
                Text("ミニチュア").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.horizontal, 24)

            if model.isRecording {
                Label("録画中", systemImage: "record.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    // MARK: 下部コントロール(片付け・シャッター・録画)

    private var bottomControls: some View {
        ZStack {
            // 中央: 押しやすい大きなシャッターボタン
            Button {
                model.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
                .shadow(color: .black.opacity(0.35), radius: 4)
            }
            .accessibilityLabel("写真を撮影")

            HStack {
                Button {
                    model.clearAll()
                } label: {
                    Label("全部片付ける", systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(model.placements.isEmpty)
                .opacity(model.placements.isEmpty ? 0.4 : 1)

                Spacer()

                Button {
                    if model.isRecording {
                        model.stopRecording()
                    } else {
                        model.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 54, height: 54)
                        if model.isRecording {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.red)
                                .frame(width: 22, height: 22)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
                .accessibilityLabel(model.isRecording ? "録画を停止" : "録画を開始")
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - 配置モデル

/// ARViewへの配置・スケール・撮影の状態を持つ(このファイル内専用)
@MainActor
@Observable
private final class ARBottlePlacementModel {
    weak var arView: ARView?
    weak var store: BottleStore?

    /// 次のタップで配置するボトル
    var pendingBottleID: Bottle.ID?
    /// false=実物大(rootEntityそのまま≒0.22m)/ true=ミニチュア(scale 0.36≒0.08m)
    var isMiniature = false
    var statusMessage = "床や机をゆっくり映して、画面をタップするとボトルを置けます"

    // 写真撮影
    var capturedImage: UIImage?
    var showPhotoSheet = false

    // 動画撮影
    var isRecording = false
    var previewController: RPPreviewViewController?
    var showVideoPreview = false
    var recordingAlertMessage = ""
    var showRecordingAlert = false

    private(set) var placements: [ARPlacedBottle] = []

    private var currentScale: Float { isMiniature ? 0.36 : 1.0 }

    // MARK: 配置

    /// タップ位置へレイキャストしてボトルを配置する
    func handleTap(at point: CGPoint) {
        guard let arView, let store,
              let id = pendingBottleID,
              let bottle = store.bottle(id: id) else { return }

        guard let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else {
            statusMessage = "平面が見つかりません。明るい場所で床や机をゆっくり映してください"
            return
        }

        let controller = BottleSceneController(
            config: bottle.sceneConfig,
            photos: store.photoCGImages(for: bottle)
        )
        // スケール用のホルダーで包む(controller側のtransformを壊さない)
        let holder = Entity()
        holder.addChild(controller.rootEntity)
        holder.scale = SIMD3<Float>(repeating: currentScale)

        let anchor = AnchorEntity(world: hit.worldTransform)
        anchor.addChild(holder)
        arView.scene.addAnchor(anchor)

        placements.append(ARPlacedBottle(anchor: anchor, holder: holder, controller: controller))
        statusMessage = "「\(bottle.title)」を置きました(\(placements.count)本)"
        Haptics.medium()
    }

    /// サイズ切替を既存の配置すべてに反映する
    func applyScaleToAll() {
        for placement in placements {
            placement.holder.scale = SIMD3<Float>(repeating: currentScale)
        }
        Haptics.tap()
    }

    /// 配置済みボトルを一括で取り除く
    func clearAll() {
        guard let arView else { return }
        for placement in placements {
            arView.scene.removeAnchor(placement.anchor)
        }
        placements.removeAll()
        statusMessage = "片付けました。タップでまた置けます"
        Haptics.tap()
    }

    // MARK: 写真撮影

    func capturePhoto() {
        guard let arView else { return }
        Haptics.tap()
        arView.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let self, let image else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                self.capturedImage = image
                self.showPhotoSheet = true
                Haptics.success()
            }
        }
    }

    // MARK: 動画撮影(ReplayKit・マイクなし)

    func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            recordingAlertMessage = "この端末では画面収録を利用できません。写真撮影をご利用ください。"
            showRecordingAlert = true
            return
        }
        recorder.isMicrophoneEnabled = false
        Haptics.tap()
        recorder.startRecording { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.recordingAlertMessage = "動画撮影を開始できませんでした。写真撮影をご利用ください。"
                    self.showRecordingAlert = true
                } else {
                    self.isRecording = true
                }
            }
        }
    }

    func stopRecording() {
        Haptics.tap()
        RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = false
                if let preview, error == nil {
                    self.previewController = preview
                    self.showVideoPreview = true
                } else {
                    self.recordingAlertMessage = "動画を保存できませんでした。写真撮影をご利用ください。"
                    self.showRecordingAlert = true
                }
            }
        }
    }

    // MARK: 終了処理

    func tearDown() {
        if isRecording {
            RPScreenRecorder.shared().stopRecording { _, _ in }
            isRecording = false
        }
        arView?.session.pause()
    }
}

/// 配置済みボトル1本分の参照
private struct ARPlacedBottle {
    let anchor: AnchorEntity
    let holder: Entity
    let controller: BottleSceneController
}

// MARK: - ARView コンテナ

private struct ARBottleViewContainer: UIViewRepresentable {
    let model: ARBottlePlacementModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        arView.session.run(config)

        // コーチングオーバーレイ(水平面を探す誘導)
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
        ])

        // タップで配置
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        model.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject {
        let model: ARBottlePlacementModel

        init(model: ARBottlePlacementModel) {
            self.model = model
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            model.handleTap(at: recognizer.location(in: view))
        }
    }
}

// MARK: - 写真結果シート

private struct ARPhotoResultSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("写真を撮影しました")
                .font(.headline)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

            Label("フォトライブラリに保存済み", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ShareLink(
                item: Image(uiImage: image),
                preview: SharePreview("Summer Bottle のAR写真", image: Image(uiImage: image))
            ) {
                Label("共有する", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.ocean, in: Capsule())
            }
            .padding(.horizontal)

            Button("閉じる") {
                dismiss()
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 20)
    }
}

// MARK: - ReplayKit プレビューのホスト

private struct ARReplayPreviewHost: UIViewControllerRepresentable {
    let controller: RPPreviewViewController
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller.previewControllerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            onFinish()
        }
    }
}

// MARK: - シミュレータ用の説明ビュー

private struct ARUnsupportedNotice: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.nightNavy, AppTheme.deepSea],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "waterbottle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.glassTint)

                Text("AR表示は実機でお楽しみください")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("この環境ではARセッションを起動できません。iPhone本体でこの画面を開くと、床や机の上に思い出のボトルを置いて眺めたり、写真や動画に残したりできます。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
