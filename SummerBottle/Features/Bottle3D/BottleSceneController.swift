//
//  BottleSceneController.swift
//  SummerBottle
//
//  RealityKit でボトル本体と 3D シーンを組み立てる中核。
//
//  座標系の契約:
//  - rootEntity の原点 = ボトル底面中心、+Y が上(AR が平面ヒット位置へ直置きする)。
//  - rootEntity の orientation / scale は外側(Viewer / AR / Export)が操作するため、
//    このクラスは一切変更しない。内部アニメーション(波・雲・コルク等)はすべて
//    子エンティティに対して行う。
//  - ガラスは内容物より後にシーンへ追加する(透過描画順)。ガラスに
//    Collision / InputTarget は付けない。
//  - フォトカードには CollisionComponent + InputTargetComponent を付与し、
//    photoID(for:) はエンティティ階層を親方向に遡って判定する。
//

import Foundation
import UIKit
import SwiftUI
import RealityKit
import simd

@MainActor
final class BottleSceneController {

    /// ルートエンティティ。RealityView の content や ARView のシーンへ追加する。
    let rootEntity: Entity

    private(set) var isCorkOpen: Bool = false

    /// ボトル全高(メートル)。カメラ距離の目安。standard で約 0.24。
    var bottleHeight: Float { geometry.totalHeight }

    // MARK: - 内部状態

    private var config: SceneConfig
    private var geometry: BottleGeometry

    /// 内容物すべての親(シェイク時の揺れはこのノードに適用)
    private var contentRoot = Entity()
    /// 瓶口の高さに固定される親。コルクの開閉はこの子(corkEntity)を動かす。
    private var corkPivot = Entity()
    private var corkEntity = Entity()

    // applyTilt の対象
    private var seaTiltEntity: Entity?
    private var seaBaseOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var sandTiltEntity: Entity?
    private var tiltOffsetTargets: [TiltOffsetTarget] = []
    private var baselinePitch: Float?

    private struct TiltOffsetTarget {
        let entity: Entity
        let basePosition: SIMD3<Float>
        let factor: Float
    }

    private static let photoCardNamePrefix = "photoCard:"

    // MARK: - 初期化 / 更新

    init(config: SceneConfig, photos: [UUID: CGImage]) {
        self.config = config
        self.geometry = BottleGeometry.geometry(for: config.bottleType)
        rootEntity = Entity()
        rootEntity.name = "bottleRoot"
        rebuild(photos: photos)
    }

    /// 構成変更時に中身を作り直す
    func update(config: SceneConfig, photos: [UUID: CGImage]) {
        self.config = config
        self.geometry = BottleGeometry.geometry(for: config.bottleType)
        rebuild(photos: photos)
    }

    // MARK: - 傾き連動

    /// 端末の傾き(ラジアン)に応じて水面・砂・雲・光・フォトカードをわずかに動かす
    func applyTilt(pitch: Float, roll: Float) {
        // 最初に受け取った pitch を基準姿勢とする(端末を構えた姿勢からの差分に反応)
        if baselinePitch == nil { baselinePitch = pitch }
        let deltaPitch = clampf(pitch - (baselinePitch ?? 0), -0.6, 0.6)
        let deltaRoll = clampf(roll, -0.6, 0.6)

        // 水面: roll / pitch 方向へ微傾斜(stormy の基本傾斜に重ねる)
        let waterZ = clampf(-deltaRoll * 0.22, -0.09, 0.09)
        let waterX = clampf(deltaPitch * 0.16, -0.07, 0.07)
        let tiltQuat = simd_quatf(angle: waterZ, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: waterX, axis: SIMD3<Float>(1, 0, 0))
        seaTiltEntity?.orientation = tiltQuat * seaBaseOrientation
        sandTiltEntity?.orientation = simd_quatf(angle: waterZ * 0.4, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: waterX * 0.4, axis: SIMD3<Float>(1, 0, 0))

        // 雲・フォトカード・補助光: ごくわずかな平行移動
        let offset = SIMD3<Float>(deltaRoll, 0, deltaPitch)
        for target in tiltOffsetTargets {
            target.entity.position = target.basePosition + offset * target.factor
        }
    }

    // MARK: - シェイク演出

    /// シェイク演出。config.particle(none ならシーンに合った既定)のバーストを発生させる
    func triggerShake() {
        let kind = config.particle == .none ? SceneParticles.defaultKind(for: config) : config.particle
        spawnBurst(
            kind: kind,
            at: SIMD3<Float>(0, floorY + geometry.contentHeight * 0.45, 0),
            in: contentRoot
        )
        wobbleContent()
    }

    private func spawnBurst(kind: ParticleKind, at position: SIMD3<Float>, in parent: Entity) {
        let entity = Entity()
        entity.name = "burstParticles"
        entity.position = position
        entity.components.set(
            SceneParticles.burstComponent(
                kind: kind,
                radius: geometry.contentRadius,
                height: geometry.contentHeight
            )
        )
        parent.addChild(entity)
        // 短時間だけ放出して、残った粒が消えてから片付ける
        Task { [weak entity] in
            try? await Task.sleep(for: .milliseconds(600))
            if let entity, var component = entity.components[ParticleEmitterComponent.self] {
                component.isEmitting = false
                entity.components.set(component)
            }
            try? await Task.sleep(for: .seconds(4))
            entity?.removeFromParent()
        }
    }

    /// 中身全体を小さく揺らす
    private func wobbleContent() {
        let content = contentRoot
        let parent = rootEntity
        var lean = Transform()
        lean.rotation = simd_quatf(angle: 0.05, axis: SIMD3<Float>(0, 0, 1))
        content.move(to: lean, relativeTo: parent, duration: 0.12, timingFunction: .easeInOut)
        Task {
            try? await Task.sleep(for: .milliseconds(130))
            var counter = Transform()
            counter.rotation = simd_quatf(angle: -0.04, axis: SIMD3<Float>(0, 0, 1))
            content.move(to: counter, relativeTo: parent, duration: 0.14, timingFunction: .easeInOut)
            try? await Task.sleep(for: .milliseconds(150))
            content.move(to: Transform(), relativeTo: parent, duration: 0.18, timingFunction: .easeInOut)
        }
    }

    // MARK: - 栓の開閉

    /// 栓の開閉(アニメーション付き)
    func setCorkOpen(_ open: Bool) {
        guard open != isCorkOpen else { return }
        isCorkOpen = open
        let target = open ? corkOpenTransform : Transform()
        corkEntity.move(to: target, relativeTo: corkPivot, duration: 0.55, timingFunction: .easeInOut)
        if open {
            // 開栓の瞬間、瓶口から小さな泡がはじける
            spawnBurst(
                kind: .bubbles,
                at: SIMD3<Float>(0, geometry.neckTopY + 0.012, 0),
                in: rootEntity
            )
        }
    }

    private var corkOpenTransform: Transform {
        var transform = Transform()
        transform.translation = SIMD3<Float>(0.014, geometry.totalHeight * 0.28, 0.010)
        transform.rotation = simd_quatf(angle: 0.5, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: 0.25, axis: SIMD3<Float>(1, 0, 0))
        return transform
    }

    // MARK: - フォトカード判定

    /// タップされたエンティティがフォトカードなら対応する BottlePhoto.id を返す
    /// (エンティティ階層を親方向に遡って判定する)
    func photoID(for entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let node = current {
            if node.name.hasPrefix(Self.photoCardNamePrefix) {
                let idString = String(node.name.dropFirst(Self.photoCardNamePrefix.count))
                if let uuid = UUID(uuidString: idString) {
                    return uuid
                }
            }
            current = node.parent
        }
        return nil
    }

    // MARK: - シーン再構築

    /// 砂の層の厚み(sandAmount 0...1)
    private var sandHeight: Float {
        let amount = Float(max(0, min(1, config.sandAmount)))
        return amount > 0.001 ? 0.003 + amount * 0.012 : 0
    }

    /// 地面の高さ(砂の上面。オブジェクトの y=0 のマッピング先)
    private var floorY: Float { geometry.contentBaseY + sandHeight }

    private func rebuild(photos: [UUID: CGImage]) {
        for child in Array(rootEntity.children) {
            child.removeFromParent()
        }
        seaTiltEntity = nil
        sandTiltEntity = nil
        tiltOffsetTargets = []
        seaBaseOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

        // 1) 内容物(ガラスより先に追加する)
        contentRoot = Entity()
        contentRoot.name = "content"
        rootEntity.addChild(contentRoot)

        buildSky()
        buildSandAndSea()
        buildWeather()
        buildObjects(photos: photos)
        buildLighting()
        buildAmbientParticles()

        // 2) ラベル(ガラスの外側に貼る紙)
        buildLabel()

        // 3) ガラス(内容物より後 = 透過描画順)
        rootEntity.addChild(geometry.makeGlassEntity())

        // 4) コルク
        corkPivot = Entity()
        corkPivot.name = "corkPivot"
        corkPivot.position = SIMD3<Float>(0, geometry.neckTopY, 0)
        rootEntity.addChild(corkPivot)
        corkEntity = geometry.makeCorkEntity()
        corkPivot.addChild(corkEntity)
        // 開いた状態のまま再構築されたら、開いた姿勢で置き直す
        corkEntity.transform = isCorkOpen ? corkOpenTransform : Transform()
    }

    // MARK: 空

    private func buildSky() {
        // 空の円筒が胴(ガラス)より上・外へはみ出すと肩に明るい帯が出るため、
        // 必ず胴の内側に収める
        let skyRadius: Float = geometry.isSpherical
            ? geometry.contentRadius * 0.98
            : min(geometry.contentRadius * 1.06, geometry.bodyRadius - 0.004)
        let skyTop: Float = geometry.isSpherical
            ? geometry.contentBaseY + geometry.contentHeight
            : geometry.bodyHeight - 0.006
        let skyHeight = max(skyTop - geometry.contentBaseY, 0.02)
        let baseColor = UIColor(hex: config.skyColorHex)

        // 内向き円筒: X を負スケールにして面を裏返す。
        // 手前側の壁はカリングで消え、奥側の内面だけが背景として見える。
        // 上下2分割だと境界が線に見えるため、1本の円筒に縦グラデーションを貼る。
        let horizonColor = mixedColor(baseColor, UIColor.white, 0.28)
        let skyMaterial: UnlitMaterial
        if let texture = Self.verticalGradientTexture(top: baseColor, bottom: horizonColor) {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            skyMaterial = material
        } else {
            skyMaterial = UnlitMaterial(color: baseColor)
        }
        let sky = ModelEntity(
            mesh: .generateCylinder(height: skyHeight, radius: skyRadius),
            materials: [skyMaterial]
        )
        sky.position = SIMD3<Float>(0, geometry.contentBaseY + skyHeight / 2, 0)
        sky.scale = SIMD3<Float>(-1, 1, 1)
        contentRoot.addChild(sky)

        guard config.timeOfDay == .night else { return }

        // 星(小さな発光球を黄金角で散らす)
        let starMaterial = UnlitMaterial(color: UIColor(hex: "#FFF7DE"))
        for index in 0..<14 {
            let t = Float(index)
            let angle = t * 2.399 + 0.6
            let radius = skyRadius * 0.9
            let normalizedY = 0.55 + 0.4 * abs(sinf(t * 1.7))
            let star = ModelEntity(
                mesh: .generateSphere(radius: 0.0008 + 0.0006 * abs(sinf(t * 2.3))),
                materials: [starMaterial]
            )
            star.position = SIMD3<Float>(
                cosf(angle) * radius,
                geometry.contentBaseY + skyHeight * min(normalizedY, 0.96),
                sinf(angle) * radius
            )
            contentRoot.addChild(star)
        }

        // 月
        let moon = ModelEntity(
            mesh: .generateSphere(radius: geometry.contentRadius * 0.14),
            materials: [UnlitMaterial(color: UIColor(hex: "#FFF3C4"))]
        )
        moon.position = SIMD3<Float>(
            -skyRadius * 0.45,
            geometry.contentBaseY + skyHeight * 0.88,
            -skyRadius * 0.5
        )
        contentRoot.addChild(moon)
    }

    // MARK: 砂と海

    private func buildSandAndSea() {
        if sandHeight > 0 {
            let sandTilt = Entity()
            sandTilt.name = "sandTilt"
            sandTilt.position = SIMD3<Float>(0, geometry.contentBaseY, 0)
            let sand = ModelEntity(
                mesh: .generateCylinder(height: sandHeight, radius: geometry.contentRadius * 1.02),
                materials: [BottleGeometry.matteMaterial(hex: "#F0E0BC", roughness: 1.0)]
            )
            sand.position = SIMD3<Float>(0, sandHeight / 2, 0)
            sandTilt.addChild(sand)
            contentRoot.addChild(sandTilt)
            sandTiltEntity = sandTilt
        }

        guard config.hasSea else { return }

        let seaThickness = max(geometry.contentHeight * 0.10, 0.008)
        let tilt = Entity()
        tilt.name = "seaTilt"
        tilt.position = SIMD3<Float>(0, floorY, 0)
        if config.weather == .stormy {
            // 台風前: 波が傾いたままになる
            seaBaseOrientation = simd_quatf(angle: 0.10, axis: SIMD3<Float>(0, 0, 1))
        }
        tilt.orientation = seaBaseOrientation

        let bob = Entity()
        let slab = ModelEntity(
            mesh: .generateCylinder(height: seaThickness, radius: geometry.contentRadius),
            materials: [BottleGeometry.translucentMaterial(hex: config.seaColorHex, opacity: 0.55, roughness: 0.1)]
        )
        slab.position = SIMD3<Float>(0, seaThickness / 2, 0)
        bob.addChild(slab)
        tilt.addChild(bob)
        contentRoot.addChild(tilt)
        seaTiltEntity = tilt

        // 波: ゆっくり上下+微傾斜のループ
        addWaveAnimation(
            to: bob,
            amplitude: seaThickness * 0.18,
            duration: config.weather == .stormy ? 1.3 : 2.6
        )
    }

    // MARK: 天気

    private func buildWeather() {
        switch config.weather {
        case .sunny, .cloudy:
            break // 光量・色で表現(buildLighting)
        case .rain:
            buildRainDroplets()
        case .shower:
            buildStormClouds(low: false, withLightning: true)
            buildRainDroplets()
        case .stormy:
            buildStormClouds(low: true, withLightning: false)
        }
        if config.timeOfDay == .morning {
            buildMorningMist()
        }
    }

    /// 瓶の内側の水滴
    private func buildRainDroplets() {
        let material = BottleGeometry.translucentMaterial(hex: "#DDF2F8", opacity: 0.5, roughness: 0.1)
        let radius = geometry.bodyRadius * 0.94
        for index in 0..<20 {
            let t = Float(index)
            let angle = t * 2.399 + 0.7
            let y = geometry.contentBaseY + 0.008
                + fmodf(t * 0.019, max(geometry.bodyHeight * 0.72, 0.02))
            let droplet = ModelEntity(
                mesh: .generateSphere(radius: 0.0012 + 0.0005 * abs(sinf(t * 1.3))),
                materials: [material]
            )
            droplet.position = SIMD3<Float>(cosf(angle) * radius, y, sinf(angle) * radius)
            droplet.scale = SIMD3<Float>(1, 1.6, 0.6)
            contentRoot.addChild(droplet)
        }
    }

    /// 暗い雲(shower は高め+稲光、stormy は低く垂れ込める)
    private func buildStormClouds(low: Bool, withLightning: Bool) {
        let cloudHex = low ? "#5A6472" : "#6E7787"
        let holder = Entity()
        holder.name = "stormCloud"
        let basePosition = SIMD3<Float>(
            0,
            geometry.contentBaseY + geometry.contentHeight * (low ? 0.62 : 0.82),
            0
        )
        holder.position = basePosition

        let scale = geometry.miniatureScale
        let material = BottleGeometry.matteMaterial(hex: cloudHex, roughness: 1.0)
        let puffs: [(SIMD3<Float>, Float)] = [
            (SIMD3<Float>(-0.013, 0.000, 0.004), 0.0100),
            (SIMD3<Float>(0.000, 0.004, -0.003), 0.0130),
            (SIMD3<Float>(0.012, 0.000, 0.003), 0.0092),
            (SIMD3<Float>(0.021, -0.002, -0.004), 0.0070),
        ]
        for (offset, radius) in puffs {
            let puff = ModelEntity(mesh: .generateSphere(radius: radius * scale), materials: [material])
            puff.position = offset * scale
            puff.scale = SIMD3<Float>(1, 0.8, 1)
            holder.addChild(puff)
        }

        if withLightning {
            // 明滅する稲光(発光球のスケールを脈動させる)+弱い点光源
            let flash = ModelEntity(
                mesh: .generateSphere(radius: 0.0045 * scale),
                materials: [UnlitMaterial(color: UIColor(hex: "#FFF6C8"))]
            )
            flash.position = SIMD3<Float>(0.002, -0.006, 0.002) * scale
            holder.addChild(flash)
            addPulseAnimation(to: flash, fromScale: 0.05, toScale: 1.0, duration: 0.38)

            let light = PointLight()
            light.light.color = UIColor(hex: "#FFF2B8")
            light.light.intensity = 8
            light.light.attenuationRadius = 0.5
            light.position = flash.position
            holder.addChild(light)
        }

        contentRoot.addChild(holder)
        tiltOffsetTargets.append(
            TiltOffsetTarget(entity: holder, basePosition: basePosition, factor: 0.006)
        )
    }

    /// 朝の薄霧(半透明の板)
    private func buildMorningMist() {
        let mistLevels: [(Float, Float)] = [(0.32, 0.12), (0.52, 0.08)]
        for (level, opacity) in mistLevels {
            let mist = ModelEntity(
                mesh: .generateCylinder(height: 0.0008, radius: geometry.contentRadius * 0.98),
                materials: [BottleGeometry.translucentMaterial(hex: "#FFFFFF", opacity: opacity, roughness: 1.0)]
            )
            mist.position = SIMD3<Float>(0, floorY + geometry.contentHeight * level, 0)
            contentRoot.addChild(mist)
        }
    }

    // MARK: ミニチュアとフォトカード

    private func buildObjects(photos: [UUID: CGImage]) {
        let objectsRoot = Entity()
        objectsRoot.name = "objects"
        contentRoot.addChild(objectsRoot)

        let placeRadius = geometry.contentRadius * 0.72
        let yRange = geometry.contentHeight * 0.78

        for object in config.objects {
            let holder = Entity()

            // 正規化座標 → 実寸(水平は長さ1にクランプ)
            var xz = SIMD2<Float>(object.position.x, object.position.z)
            let length = simd_length(xz)
            if length > 1 { xz /= length }
            let ny = max(0, min(1, object.position.y))
            let basePosition = SIMD3<Float>(
                xz.x * placeRadius,
                floorY + ny * yRange,
                xz.y * placeRadius
            )
            holder.position = basePosition
            holder.orientation = simd_quatf(angle: object.rotationY, axis: SIMD3<Float>(0, 1, 0))
            let scale = max(object.scale, 0.05) * geometry.miniatureScale
            holder.scale = SIMD3<Float>(repeating: scale)

            if object.type == .photoCard {
                holder.name = Self.photoCardNamePrefix + (object.photoID?.uuidString ?? "")
                let card = makePhotoCard(image: object.photoID.flatMap { photos[$0] })
                holder.addChild(card.entity)
                // タップ判定(Viewer の SpatialTapGesture().targetedToAnyEntity() 用)
                holder.components.set(CollisionComponent(shapes: [card.shape]))
                holder.components.set(InputTargetComponent())
                tiltOffsetTargets.append(
                    TiltOffsetTarget(entity: holder, basePosition: basePosition, factor: 0.0035)
                )
            } else {
                let prefab = MiniaturePrefabs.make(object.type, config: config)
                if object.type == .cloud {
                    // 雲はゆっくり漂わせる
                    let drift = Entity()
                    drift.addChild(prefab)
                    holder.addChild(drift)
                    addDriftAnimation(to: drift, amplitude: 0.0018, duration: 3.6)
                    tiltOffsetTargets.append(
                        TiltOffsetTarget(entity: holder, basePosition: basePosition, factor: 0.006)
                    )
                } else {
                    holder.addChild(prefab)
                }
            }
            objectsRoot.addChild(holder)
        }
    }

    /// 写真テクスチャ付きの白枠カード(ポラロイド風)。原点=足元中心。
    private func makePhotoCard(image: CGImage?) -> (entity: Entity, shape: ShapeResource) {
        let aspect: Float
        if let image, image.height > 0 {
            aspect = Float(image.width) / Float(image.height)
        } else {
            aspect = 0.75
        }
        let maxEdge: Float = 0.052
        var photoWidth = maxEdge
        var photoHeight = maxEdge
        if aspect >= 1 {
            photoHeight = maxEdge / aspect
        } else {
            photoWidth = maxEdge * aspect
        }
        let border: Float = 0.003
        let frameWidth = photoWidth + border * 2
        let frameHeight = photoHeight + border * 2 + 0.007 // 下だけ厚く

        let card = Entity()
        card.name = "photoCardVisual"
        card.orientation = simd_quatf(angle: -0.08, axis: SIMD3<Float>(1, 0, 0))
        let centerY = frameHeight / 2

        // 白枠
        let frame = ModelEntity(
            mesh: .generateBox(width: frameWidth, height: frameHeight, depth: 0.0018, cornerRadius: 0.0008),
            materials: [BottleGeometry.matteMaterial(hex: "#FBFBF8", roughness: 0.6)]
        )
        frame.position = SIMD3<Float>(0, centerY, 0)
        card.addChild(frame)

        // 写真面(テクスチャ生成に失敗したら無地の板でフォールバック)
        let photoMaterial: any RealityKit.Material
        if let image,
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            var unlit = UnlitMaterial()
            unlit.color = .init(tint: .white, texture: .init(texture))
            photoMaterial = unlit
        } else {
            photoMaterial = BottleGeometry.matteMaterial(hex: "#C9D6DC", roughness: 0.8)
        }
        let photo = ModelEntity(
            mesh: .generatePlane(width: photoWidth, height: photoHeight, cornerRadius: 0.0006),
            materials: [photoMaterial]
        )
        photo.position = SIMD3<Float>(0, frameHeight - border - photoHeight / 2, 0.0011)
        card.addChild(photo)

        let shape = ShapeResource
            .generateBox(width: frameWidth, height: frameHeight, depth: 0.008)
            .offsetBy(translation: SIMD3<Float>(0, centerY, 0))
        return (card, shape)
    }

    // MARK: ライティング

    private func buildLighting() {
        let lightRoot = Entity()
        lightRoot.name = "lights"
        rootEntity.addChild(lightRoot)

        var intensity: Float
        var colorHex: String
        var from: SIMD3<Float>
        switch config.timeOfDay {
        case .morning:
            intensity = 2800; colorHex = "#FFF2DC"; from = SIMD3<Float>(0.5, 0.9, 0.6)
        case .daytime:
            intensity = 5200; colorHex = "#FFFFFF"; from = SIMD3<Float>(0.45, 1.0, 0.4)
        case .evening:
            // 低い角度からのオレンジ光(長い影の印象)
            intensity = 3400; colorHex = "#FFB070"; from = SIMD3<Float>(-0.9, 0.28, 0.55)
        case .night:
            intensity = 1000; colorHex = "#A9BBE8"; from = SIMD3<Float>(0.3, 0.9, 0.45)
        }
        switch config.weather {
        case .sunny:
            break
        case .cloudy:
            intensity *= 0.60
        case .rain, .shower:
            intensity *= 0.45
        case .stormy:
            intensity *= 0.50
        }

        let sun = DirectionalLight()
        var sunColor = UIColor(hex: colorHex)
        if config.weather != .sunny {
            // 曇天・雨天は白っぽく柔らかい光へ寄せる
            sunColor = mixedColor(sunColor, UIColor(hex: "#DCE4EC"), 0.5)
        }
        sun.light.color = sunColor
        sun.light.intensity = intensity
        sun.look(at: .zero, from: from, relativeTo: nil)
        lightRoot.addChild(sun)

        // 内容物を柔らかく持ち上げる補助光(傾きでわずかに動く)
        let fill = PointLight()
        fill.light.color = UIColor(hex: config.timeOfDay == .night ? "#BBC8E8" : "#FFF6E8")
        fill.light.intensity = config.timeOfDay == .night ? 120 : 250
        fill.light.attenuationRadius = 1.5
        let fillBase = SIMD3<Float>(
            geometry.contentRadius * 0.8,
            geometry.totalHeight * 0.85,
            geometry.contentRadius * 2.4
        )
        fill.position = fillBase
        lightRoot.addChild(fill)
        tiltOffsetTargets.append(
            TiltOffsetTarget(entity: fill, basePosition: fillBase, factor: 0.012)
        )

        // ランタンボトル: 内部の暖色光+豆電球
        if config.bottleType == .lantern {
            let inner = PointLight()
            inner.light.color = UIColor(hex: "#FFC46B")
            inner.light.intensity = config.timeOfDay == .night ? 60 : 35
            inner.light.attenuationRadius = 0.6
            let bulbPosition = SIMD3<Float>(0, geometry.contentBaseY + geometry.contentHeight * 0.74, 0)
            inner.position = bulbPosition
            lightRoot.addChild(inner)

            let bulb = ModelEntity(
                mesh: .generateSphere(radius: 0.004),
                materials: [UnlitMaterial(color: UIColor(hex: "#FFDF9E"))]
            )
            bulb.position = bulbPosition
            contentRoot.addChild(bulb)
        }
    }

    // MARK: パーティクル(常時)

    private func buildAmbientParticles() {
        guard let component = SceneParticles.ambientComponent(
            kind: config.particle,
            radius: geometry.contentRadius,
            height: geometry.contentHeight
        ) else { return }
        let entity = Entity()
        entity.name = "ambientParticles"
        entity.position = SIMD3<Float>(0, floorY + geometry.contentHeight * 0.45, 0)
        entity.components.set(component)
        contentRoot.addChild(entity)
    }

    // MARK: ラベル

    private func buildLabel() {
        let text = config.labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // フォトカードの正面を隠さないよう、ラベルは小さく・低い位置に貼る
        let aged = config.bottleType == .drift
        let width = geometry.bodyRadius * 1.15
        let height = geometry.bodyHeight * 0.22

        // ImageRenderer でテクスチャ生成、失敗時は白板フォールバック
        let material: any RealityKit.Material
        if let texture = Self.labelTexture(text: text, aged: aged) {
            var pbm = PhysicallyBasedMaterial()
            pbm.baseColor = .init(tint: .white, texture: .init(texture))
            pbm.roughness = .init(floatLiteral: 0.8)
            pbm.metallic = .init(floatLiteral: 0)
            material = pbm
        } else {
            material = BottleGeometry.matteMaterial(hex: aged ? "#EFE3C2" : "#FFFFFF", roughness: 0.8)
        }

        let label = ModelEntity(
            mesh: .generatePlane(width: width, height: height, cornerRadius: height * 0.08),
            materials: [material]
        )
        label.name = "bottleLabel"
        label.position = SIMD3<Float>(0, geometry.bodyHeight * 0.18, geometry.bodyRadius + 0.0015)
        if aged {
            // 漂流瓶は少し斜めに貼られた古紙ラベル
            label.orientation = simd_quatf(angle: -0.06, axis: SIMD3<Float>(0, 0, 1))
        }
        rootEntity.addChild(label)
    }

    /// 空の円筒用の縦グラデーション(上=空色、下=地平線の明るい色)
    private static func verticalGradientTexture(top: UIColor, bottom: UIColor) -> TextureResource? {
        let size = CGSize(width: 8, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [top.cgColor, bottom.cgColor] as CFArray,
                locations: [0, 1]
            ) else {
                top.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                return
            }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    private static func labelTexture(text: String, aged: Bool) -> TextureResource? {
        let canvas = BottleLabelCanvas(text: text, aged: aged)
            .frame(width: 440, height: 240)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let uiImage = renderer.uiImage, let cgImage = uiImage.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    // MARK: - アニメーションヘルパ

    /// 上下ゆらゆら(波)
    private func addWaveAnimation(to entity: Entity, amplitude: Float, duration: TimeInterval) {
        var from = entity.transform
        var to = entity.transform
        from.translation.y -= amplitude / 2
        to.translation.y += amplitude / 2
        to.rotation = simd_quatf(angle: 0.02, axis: SIMD3<Float>(0, 0, 1))
        playLoop(on: entity, from: from, to: to, duration: duration)
    }

    /// 左右ふわふわ(雲)
    private func addDriftAnimation(to entity: Entity, amplitude: Float, duration: TimeInterval) {
        var from = entity.transform
        var to = entity.transform
        from.translation.x -= amplitude
        to.translation.x += amplitude
        to.translation.y += amplitude * 0.4
        playLoop(on: entity, from: from, to: to, duration: duration)
    }

    /// スケールの脈動(稲光)
    private func addPulseAnimation(to entity: Entity, fromScale: Float, toScale: Float, duration: TimeInterval) {
        var from = entity.transform
        var to = entity.transform
        from.scale = SIMD3<Float>(repeating: fromScale)
        to.scale = SIMD3<Float>(repeating: toScale)
        playLoop(on: entity, from: from, to: to, duration: duration)
    }

    private func playLoop(on entity: Entity, from: Transform, to: Transform, duration: TimeInterval) {
        let animation = FromToByAnimation<Transform>(
            from: from,
            to: to,
            duration: duration,
            timing: .easeInOut,
            bindTarget: .transform,
            repeatMode: .autoReverse
        )
        guard let resource = try? AnimationResource.generate(with: animation) else { return }
        entity.playAnimation(resource.repeat(), transitionDuration: 0, startsPaused: false)
    }
}

// MARK: - ラベルの描画元(ImageRenderer 用)

fileprivate struct BottleLabelCanvas: View {
    let text: String
    let aged: Bool

    private var inkColor: Color { Color(hex: aged ? "#5A4A32" : "#3A4A55") }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(aged ? Color(hex: "#EFE3C2") : Color.white)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(aged ? Color(hex: "#B39B6A") : Color(hex: "#B8D4DE"), lineWidth: 3)
                .padding(8)
            VStack(spacing: 12) {
                Text("SUMMER BOTTLE")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(inkColor.opacity(0.55))
                Text(text)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(inkColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                Rectangle()
                    .fill(inkColor.opacity(0.35))
                    .frame(width: 130, height: 2)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - ファイル内ユーティリティ

fileprivate func clampf(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    min(upper, max(lower, value))
}

fileprivate func mixedColor(_ colorA: UIColor, _ colorB: UIColor, _ amount: CGFloat) -> UIColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    colorA.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    colorB.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    let t = min(1, max(0, amount))
    return UIColor(
        red: r1 + (r2 - r1) * t,
        green: g1 + (g2 - g1) * t,
        blue: b1 + (b2 - b1) * t,
        alpha: 1
    )
}
