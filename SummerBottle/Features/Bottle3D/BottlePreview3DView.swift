//
//  BottlePreview3DView.swift
//  SummerBottle
//
//  自己完結のプレビュー用3Dビュー。ドラッグで回転・ピンチで拡大縮小。
//  モーション連動・シェイク・音は含まない。作成フロー/編集画面/書き出しで使う。
//  config が変わったら controller.update でシーンを作り直す。
//

import SwiftUI
import RealityKit
import simd

struct BottlePreview3DView: View {
    private let config: SceneConfig
    private let photos: [UUID: CGImage]

    @State private var controller: BottleSceneController?
    @State private var cameraEntity: PerspectiveCamera?

    // ドラッグ回転(Y軸)
    @State private var yaw: Float = 0
    @State private var dragBaseYaw: Float = 0
    @State private var isDragging = false

    // ピンチズーム(カメラ距離の倍率)
    @State private var zoom: Float = 1
    @State private var baseZoom: Float = 1

    init(config: SceneConfig, photos: [UUID: CGImage]) {
        self.config = config
        self.photos = photos
    }

    var body: some View {
        ZStack {
            AppTheme.skyGradient(for: config.timeOfDay)

            RealityView { content in
                let ctrl = BottleSceneController(config: config, photos: photos)
                content.add(ctrl.rootEntity)

                let camera = PerspectiveCamera()
                content.add(camera)

                controller = ctrl
                cameraEntity = camera
                positionCamera(camera: camera, height: ctrl.bottleHeight)
            }
            .gesture(rotateGesture)
            .simultaneousGesture(magnifyGesture)
        }
        .onChange(of: config) { _, newConfig in
            controller?.update(config: newConfig, photos: photos)
            if let controller, let cameraEntity {
                positionCamera(camera: cameraEntity, height: controller.bottleHeight)
            }
        }
        .onChange(of: Set(photos.keys)) { _, _ in
            // 写真が後から読み込まれたとき(書き出し画面など)に反映する
            controller?.update(config: config, photos: photos)
        }
    }

    // MARK: - カメラ

    private func positionCamera(camera: PerspectiveCamera, height: Float) {
        // 瓶が画面の主役になる距離(コルク込みで少し余白が残る程度)
        let distance = height * 1.75 * zoom
        camera.look(
            at: SIMD3<Float>(0, height * 0.52, 0),
            from: SIMD3<Float>(0, height * 0.62, distance),
            relativeTo: nil
        )
    }

    // MARK: - ジェスチャ

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragBaseYaw = yaw
                }
                yaw = dragBaseYaw + Float(value.translation.width) * 0.012
                controller?.rootEntity.orientation = simd_quatf(
                    angle: yaw,
                    axis: SIMD3<Float>(0, 1, 0)
                )
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let magnification = Float(value.magnification)
                guard magnification > 0 else { return }
                // ピンチアウト(拡大)でカメラが近づく
                zoom = min(2.5, max(0.5, baseZoom / magnification))
                if let controller, let cameraEntity {
                    positionCamera(camera: cameraEntity, height: controller.bottleHeight)
                }
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }
}
