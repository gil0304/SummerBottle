//
//  MiniaturePrefabs.swift
//  SummerBottle
//
//  瓶の中に置くミニチュア3Dモデル群。
//  RealityKit のプリミティブ(box/sphere/cylinder/cone)と
//  SimpleMaterial / PhysicallyBasedMaterial / UnlitMaterial だけで
//  23種のかわいいミニチュアを作り込む。
//
//  規約:
//  - 原点 = 足元中心。全体の高さは約 0.02〜0.05m のスケール感。
//  - config.timeOfDay == .night のときは発光(提灯・街灯・窓・花火など)を強調する。
//  - photoCard は空の Entity を返す(BottleSceneController 側で写真テクスチャを貼る)。
//

import Foundation
import UIKit
import RealityKit
import simd

@MainActor
enum MiniaturePrefabs {

    /// photoCard 以外の全 SceneObjectType のミニチュアを生成する。
    /// 返す Entity は原点=足元中心、高さ約 0.02〜0.05m のスケール感。
    /// photoCard が渡されたら空の Entity を返す(コントローラが処理する)。
    static func make(_ type: SceneObjectType, config: SceneConfig) -> Entity {
        let night = config.timeOfDay == .night
        let entity: Entity
        switch type {
        case .cloud:         entity = makeCloud(night: night)
        case .fireworks:     entity = makeFireworks(night: night)
        case .mountain:      entity = makeMountain(night: night)
        case .stall:         entity = makeStall(night: night)
        case .lanternString: entity = makeLanternString(night: night)
        case .torii:         entity = makeTorii(night: night)
        case .watermelon:    entity = makeWatermelon()
        case .shavedIce:     entity = makeShavedIce()
        case .parasol:       entity = makeParasol()
        case .building:      entity = makeBuilding(night: night)
        case .photoCard:     entity = Entity() // コントローラ側で写真板を構築する
        case .table:         entity = makeTable()
        case .food:          entity = makeFood()
        case .tree:          entity = makeTree(night: night)
        case .bench:         entity = makeBench()
        case .streetLight:   entity = makeStreetLight(night: night)
        case .pool:          entity = makePool()
        case .floatRing:     entity = makeFloatRing()
        case .tent:          entity = makeTent()
        case .campfire:      entity = makeCampfire(night: night)
        case .palmTree:      entity = makePalmTree()
        case .boat:          entity = makeBoat()
        case .shell:         entity = makeShell()
        case .grass:         entity = makeGrass()
        }
        entity.name = "miniature_\(type.rawValue)"
        return entity
    }

    // MARK: - 素材ヘルパ

    /// マットな SimpleMaterial
    private static func matte(_ hex: String, roughness: Float = 0.85) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(hex: hex),
                       roughness: MaterialScalarParameter(floatLiteral: roughness),
                       isMetallic: false)
    }

    /// 発光して見える UnlitMaterial。夜は白に寄せて明るく、昼は少し落ち着かせる。
    private static func glow(_ hex: String, night: Bool) -> UnlitMaterial {
        let base = UIColor(hex: hex)
        let color = night
            ? mixColor(base, UIColor.white, 0.22)
            : mixColor(base, UIColor(white: 0.72, alpha: 1), 0.16)
        return UnlitMaterial(color: color)
    }

    /// 少しつやのある PhysicallyBasedMaterial
    private static func shiny(_ hex: String, roughness: Float = 0.3) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    /// 半透明マテリアル(プールの水・かき氷のシロップなど)
    private static func translucent(_ hex: String, opacity: Float, roughness: Float = 0.15) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// 2色の線形補間
    private static func mixColor(_ colorA: UIColor, _ colorB: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        colorA.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        colorB.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: 1)
    }

    // MARK: - 形状ヘルパ

    /// メッシュ+マテリアルから配置済みの ModelEntity を作る
    private static func part(_ mesh: MeshResource,
                             _ material: any Material,
                             at position: SIMD3<Float> = .zero,
                             rotated orientation: simd_quatf? = nil,
                             scaled scale: SIMD3<Float>? = nil) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        if let orientation { entity.orientation = orientation }
        if let scale { entity.scale = scale }
        return entity
    }

    /// 子をまとめる空のコンテナ
    private static func group(_ children: [Entity]) -> Entity {
        let container = Entity()
        for child in children { container.addChild(child) }
        return container
    }

    /// +Y 軸を任意方向へ向ける回転
    private static func alignYAxis(to direction: SIMD3<Float>) -> simd_quatf {
        let up: SIMD3<Float> = [0, 1, 0]
        let normalized = simd_normalize(direction)
        let dot = simd_dot(up, normalized)
        if dot > 0.9999 { return simd_quatf(angle: 0, axis: up) }
        if dot < -0.9999 { return simd_quatf(angle: .pi, axis: [1, 0, 0]) }
        let axis = simd_normalize(simd_cross(up, normalized))
        return simd_quatf(angle: acosf(max(-1, min(1, dot))), axis: axis)
    }

    /// 2点間を結ぶ細い円筒(紐・ロープ)
    private static func rope(from start: SIMD3<Float>,
                             to end: SIMD3<Float>,
                             radius: Float,
                             material: any Material) -> ModelEntity {
        let vector = end - start
        let length = simd_length(vector)
        let entity = ModelEntity(mesh: .generateCylinder(height: length, radius: radius),
                                 materials: [material])
        entity.position = (start + end) / 2
        entity.orientation = alignYAxis(to: vector)
        return entity
    }

    // MARK: - 入道雲

    /// 白いふわふわの球を縦に盛り上げた入道雲
    private static func makeCloud(night: Bool) -> Entity {
        let bodyMaterial = matte(night ? "#D7DFF2" : "#FFFFFF", roughness: 1.0)
        let shadeMaterial = matte(night ? "#B9C4E0" : "#ECF2F8", roughness: 1.0)
        // (中心, 半径, 下段か)
        let puffs: [(SIMD3<Float>, Float, Bool)] = [
            ([-0.0100, 0.0105,  0.0010], 0.0100, true),
            ([ 0.0005, 0.0120, -0.0020], 0.0130, true),
            ([ 0.0110, 0.0100,  0.0015], 0.0090, true),
            ([-0.0052, 0.0225,  0.0000], 0.0092, false),
            ([ 0.0062, 0.0235,  0.0010], 0.0100, false),
            ([ 0.0008, 0.0330,  0.0000], 0.0082, false),
            ([ 0.0030, 0.0405,  0.0018], 0.0052, false),
        ]
        var parts: [Entity] = []
        for (center, radius, isBottom) in puffs {
            parts.append(part(.generateSphere(radius: radius),
                              isBottom ? shadeMaterial : bodyMaterial,
                              at: center,
                              scaled: [1, isBottom ? 0.82 : 1, 1]))
        }
        return group(parts)
    }

    // MARK: - 花火

    /// 放射状の細い発光棒の束+中心球+打ち上げの尾
    private static func makeFireworks(night: Bool) -> Entity {
        let center: SIMD3<Float> = [0, 0.030, 0]
        let rodLength: Float = 0.012
        let hexes = ["#FF6FA5", "#FFD34D", "#6FD8FF", "#B08CFF", "#7DF2B0"]
        var parts: [Entity] = []

        // 打ち上げの尾(地面から中心へ立ち上る淡い光)
        parts.append(part(.generateCylinder(height: 0.017, radius: 0.00035),
                          glow("#E8CFA0", night: night),
                          at: [0, 0.0105, 0]))

        // 中心の玉
        parts.append(part(.generateSphere(radius: 0.0024),
                          glow("#FFF3C8", night: night),
                          at: center))

        // 放射方向: 真上 + 仰角リング
        var directions: [SIMD3<Float>] = [[0, 1, 0]]
        let rings: [(elevation: Float, count: Int, phase: Float)] = [
            (0.00, 6, 0.0),
            (0.70, 5, 0.6),
            (-0.60, 4, 0.8),
            (1.25, 3, 0.3),
        ]
        for ring in rings {
            for index in 0..<ring.count {
                let azimuth = ring.phase + Float(index) / Float(ring.count) * 2 * .pi
                directions.append([cosf(ring.elevation) * cosf(azimuth),
                                   sinf(ring.elevation),
                                   cosf(ring.elevation) * sinf(azimuth)])
            }
        }
        for (index, direction) in directions.enumerated() {
            let material = glow(hexes[index % hexes.count], night: night)
            parts.append(part(.generateCylinder(height: rodLength, radius: 0.0005),
                              material,
                              at: center + direction * (0.0026 + rodLength / 2),
                              rotated: alignYAxis(to: direction)))
            // 先端のきらめき
            parts.append(part(.generateSphere(radius: 0.0009),
                              material,
                              at: center + direction * (0.0026 + rodLength + 0.0008)))
        }
        return group(parts)
    }

    // MARK: - 山

    /// 緑の主峰+青い遠山+雪冠
    private static func makeMountain(night: Bool) -> Entity {
        var parts: [Entity] = []
        // 遠くの青い山
        parts.append(part(.generateCone(height: 0.022, radius: 0.013),
                          matte(night ? "#3D5A78" : "#5B7FA6"),
                          at: [0.0095, 0.011, -0.0060]))
        // 主峰(緑)
        parts.append(part(.generateCone(height: 0.030, radius: 0.018),
                          matte(night ? "#2F5E46" : "#4E8D6E"),
                          at: [0, 0.015, 0]))
        // 雪冠
        parts.append(part(.generateCone(height: 0.0100, radius: 0.0063),
                          matte("#F4F8FB", roughness: 0.7),
                          at: [0, 0.0255, 0]))
        return group(parts)
    }

    // MARK: - 屋台

    /// 木のカウンター+柱+赤白ストライプの屋根+のれん+提灯
    private static func makeStall(night: Bool) -> Entity {
        var parts: [Entity] = []
        // カウンター
        parts.append(part(.generateBox(width: 0.019, height: 0.0095, depth: 0.011, cornerRadius: 0.001),
                          matte("#C89B6C"),
                          at: [0, 0.00475, 0]))
        // 四隅の柱
        let poleMaterial = matte("#7A5230")
        for x in [Float(-0.0092), 0.0092] {
            for z in [Float(-0.0052), 0.0052] {
                parts.append(part(.generateCylinder(height: 0.021, radius: 0.0008),
                                  poleMaterial,
                                  at: [x, 0.0115, z]))
            }
        }
        // 赤白ストライプの屋根(少し前に傾ける)
        let roofTilt = simd_quatf(angle: 0.12, axis: [1, 0, 0])
        for index in 0..<5 {
            let x = -0.0088 + 0.0044 * Float(index)
            let hex = index % 2 == 0 ? "#E0453A" : "#F6F2E7"
            parts.append(part(.generateBox(width: 0.0044, height: 0.0015, depth: 0.016),
                              matte(hex, roughness: 0.7),
                              at: [x, 0.0228, 0.0015],
                              rotated: roofTilt))
        }
        // のれん
        parts.append(part(.generateBox(width: 0.019, height: 0.0042, depth: 0.0006),
                          matte("#E0453A", roughness: 0.75),
                          at: [0, 0.0192, 0.0062]))
        for x in [Float(-0.004), 0.004] {
            parts.append(part(.generateBox(width: 0.0008, height: 0.0042, depth: 0.0007),
                              matte("#F6F2E7"),
                              at: [x, 0.0192, 0.00625]))
        }
        // 軒先の提灯
        parts.append(part(.generateSphere(radius: 0.0016),
                          glow("#FF9838", night: night),
                          at: [0.0085, 0.0166, 0.0062]))
        return group(parts)
    }

    // MARK: - 提灯(連なり)

    /// 2本の柱の間に、橙色に発光する提灯を弧状に4個吊るす
    private static func makeLanternString(night: Bool) -> Entity {
        var parts: [Entity] = []
        let poleMaterial = matte("#6E4B2F")
        let ropeMaterial = matte("#5B4636", roughness: 1.0)
        let capMaterial = matte("#33302E")

        // 両端の柱
        for x in [Float(-0.014), 0.014] {
            parts.append(part(.generateCylinder(height: 0.030, radius: 0.0009),
                              poleMaterial,
                              at: [x, 0.015, 0]))
        }

        // 弧を描く吊り点
        let leftPoleTop: SIMD3<Float> = [-0.014, 0.0300, 0]
        let rightPoleTop: SIMD3<Float> = [0.014, 0.0300, 0]
        let hangPoints: [SIMD3<Float>] = [
            [-0.0105, 0.0278, 0],
            [-0.0035, 0.0262, 0],
            [ 0.0035, 0.0262, 0],
            [ 0.0105, 0.0278, 0],
        ]

        // 紐
        let chain = [leftPoleTop] + hangPoints + [rightPoleTop]
        for index in 0..<(chain.count - 1) {
            parts.append(rope(from: chain[index], to: chain[index + 1],
                              radius: 0.0003, material: ropeMaterial))
        }

        // 提灯本体(橙発光の小円筒)+上下の黒キャップ
        let lanternHexes = ["#FF9838", "#FF6E5E"]
        for (index, point) in hangPoints.enumerated() {
            let bodyCenter = point - SIMD3<Float>(0, 0.0032, 0)
            parts.append(part(.generateCylinder(height: 0.0046, radius: 0.0023),
                              glow(lanternHexes[index % 2], night: night),
                              at: bodyCenter))
            parts.append(part(.generateCylinder(height: 0.0006, radius: 0.0016),
                              capMaterial,
                              at: bodyCenter + SIMD3<Float>(0, 0.0026, 0)))
            parts.append(part(.generateCylinder(height: 0.0006, radius: 0.0016),
                              capMaterial,
                              at: bodyCenter - SIMD3<Float>(0, 0.0026, 0)))
        }
        return group(parts)
    }

    // MARK: - 鳥居

    /// 朱色の2柱+笠木・貫の2梁
    private static func makeTorii(night: Bool) -> Entity {
        let red = matte(night ? "#B23324" : "#D9402F", roughness: 0.7)
        let black = matte("#33302E")
        var parts: [Entity] = []
        // 柱
        for x in [Float(-0.0095), 0.0095] {
            parts.append(part(.generateCylinder(height: 0.0285, radius: 0.0021),
                              red,
                              at: [x, 0.014, 0]))
            // 根巻き(黒い台座)
            parts.append(part(.generateCylinder(height: 0.0014, radius: 0.0027),
                              black,
                              at: [x, 0.0007, 0]))
        }
        // 笠木(上の梁)
        parts.append(part(.generateBox(width: 0.0315, height: 0.0028, depth: 0.0044, cornerRadius: 0.0008),
                          red,
                          at: [0, 0.0296, 0]))
        // 島木の上の黒い笠
        parts.append(part(.generateBox(width: 0.0330, height: 0.0013, depth: 0.0048, cornerRadius: 0.0006),
                          black,
                          at: [0, 0.0316, 0]))
        // 貫(下の梁)
        parts.append(part(.generateBox(width: 0.0265, height: 0.0024, depth: 0.0036, cornerRadius: 0.0006),
                          red,
                          at: [0, 0.0234, 0]))
        // 額束(中央の短い柱)
        parts.append(part(.generateBox(width: 0.0022, height: 0.0043, depth: 0.0030),
                          red,
                          at: [0, 0.0265, 0]))
        return group(parts)
    }

    // MARK: - スイカ

    /// 緑球+濃緑の縞+正面のカット面(白い皮・赤い実・黒い種)
    private static func makeWatermelon() -> Entity {
        var parts: [Entity] = []
        // 本体
        parts.append(part(.generateSphere(radius: 0.0095),
                          shiny("#3E9B4F", roughness: 0.35),
                          at: [0, 0.0095, 0]))
        // 縞: 薄くつぶした濃緑の球を本体よりわずかに大きくして重ねる
        let stripeMaterial = shiny("#1F6B33", roughness: 0.4)
        for yaw in [Float(0.35), 1.40, 2.44] {
            parts.append(part(.generateSphere(radius: 0.0096),
                              stripeMaterial,
                              at: [0, 0.0095, 0],
                              rotated: simd_quatf(angle: yaw, axis: [0, 1, 0]),
                              scaled: [0.16, 1.0, 1.0]))
        }
        // カット面(正面 +Z 側): 白い皮の円盤 → 赤い実の円盤
        let faceRotation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        parts.append(part(.generateCylinder(height: 0.0008, radius: 0.0080),
                          matte("#F0F6E8", roughness: 0.6),
                          at: [0, 0.0095, 0.00965],
                          rotated: faceRotation))
        parts.append(part(.generateCylinder(height: 0.0008, radius: 0.0072),
                          shiny("#F04C4C", roughness: 0.45),
                          at: [0, 0.0095, 0.01045],
                          rotated: faceRotation))
        // 黒い種
        let seedMaterial = matte("#26221E", roughness: 0.5)
        let seedOffsets: [SIMD2<Float>] = [
            [0.0000, 0.0040], [0.0026, 0.0018], [-0.0026, 0.0018],
            [0.0015, -0.0022], [-0.0015, -0.0022],
        ]
        for offset in seedOffsets {
            parts.append(part(.generateSphere(radius: 0.00045),
                              seedMaterial,
                              at: [offset.x, 0.0095 + offset.y, 0.0109],
                              scaled: [0.8, 1.2, 0.6]))
        }
        // ヘタ
        parts.append(part(.generateCylinder(height: 0.0032, radius: 0.0005),
                          matte("#6E8B3D"),
                          at: [0.0008, 0.0200, 0],
                          rotated: simd_quatf(angle: 0.4, axis: [0, 0, 1])))
        return group(parts)
    }

    // MARK: - かき氷

    /// 器(逆さの円錐)+白い氷の山+いちごシロップ
    private static func makeShavedIce() -> Entity {
        var parts: [Entity] = []
        let bowlMaterial = shiny("#A8D8E8", roughness: 0.25)
        // 足
        parts.append(part(.generateCylinder(height: 0.0012, radius: 0.0026),
                          bowlMaterial,
                          at: [0, 0.0006, 0]))
        // 器(円錐を逆さに)
        parts.append(part(.generateCone(height: 0.0075, radius: 0.0062),
                          bowlMaterial,
                          at: [0, 0.00455, 0],
                          rotated: simd_quatf(angle: .pi, axis: [1, 0, 0])))
        // 白い氷の山
        parts.append(part(.generateCone(height: 0.0115, radius: 0.0058),
                          matte("#FDFDFE", roughness: 1.0),
                          at: [0, 0.01355, 0]))
        // いちごシロップ(半透明の赤い円錐を上からかぶせる)
        parts.append(part(.generateCone(height: 0.0092, radius: 0.0044),
                          translucent("#FF5A6E", opacity: 0.72, roughness: 0.3),
                          at: [0, 0.0148, 0]))
        return group(parts)
    }

    // MARK: - ビーチパラソル

    /// 傾いた赤白ストライプの円錐+棒
    private static func makeParasol() -> Entity {
        var parts: [Entity] = []
        // 棒
        parts.append(part(.generateCylinder(height: 0.026, radius: 0.0008),
                          matte("#E8E3D5", roughness: 0.6),
                          at: [0, 0.013, 0]))
        // 傘(赤い円錐)
        parts.append(part(.generateCone(height: 0.0075, radius: 0.0115),
                          matte("#E0453A", roughness: 0.7),
                          at: [0, 0.02525, 0]))
        // 白い縞: 薄くつぶした白円錐を直交させて重ねる
        for yaw in [Float(0), .pi / 2] {
            parts.append(part(.generateCone(height: 0.0074, radius: 0.0117),
                              matte("#F6F2E7", roughness: 0.7),
                              at: [0, 0.02525, 0],
                              rotated: simd_quatf(angle: yaw, axis: [0, 1, 0]),
                              scaled: [0.22, 1.0, 1.0]))
        }
        // てっぺんの飾り玉
        parts.append(part(.generateSphere(radius: 0.0012),
                          matte("#E0453A"),
                          at: [0, 0.0298, 0]))
        // 全体を少し傾ける(足元原点のまま)
        let parasol = group(parts)
        parasol.orientation = simd_quatf(angle: 0.22, axis: [0, 0, 1])
        return group([parasol])
    }

    // MARK: - 建物

    /// 窓の光る小さなビル2棟+屋上アンテナ
    private static func makeBuilding(night: Bool) -> Entity {
        var parts: [Entity] = []
        // タワーA(高い方)
        parts.append(part(.generateBox(width: 0.009, height: 0.030, depth: 0.009, cornerRadius: 0.0006),
                          matte(night ? "#3A4560" : "#6B7B95", roughness: 0.7),
                          at: [-0.0040, 0.015, 0]))
        // タワーB(低い方)
        parts.append(part(.generateBox(width: 0.0065, height: 0.020, depth: 0.0065, cornerRadius: 0.0005),
                          matte(night ? "#465270" : "#8593AB", roughness: 0.7),
                          at: [0.0055, 0.010, 0.0015]))

        // 窓
        let litHexes = ["#FFD97A", "#FFC069"]
        func windowMaterial(row: Int, column: Int) -> any Material {
            if night {
                // ところどころ消灯している窓
                if (row + column * 2) % 4 == 3 { return matte("#2E3850", roughness: 0.6) }
                return glow(litHexes[(row + column) % 2], night: true)
            }
            return shiny("#CFE3F0", roughness: 0.2)
        }
        // タワーAの窓(2列×5段)
        let rowsA: [Float] = [0.0045, 0.0100, 0.0155, 0.0210, 0.0265]
        let columnsA: [Float] = [-0.0060, -0.0020]
        for (rowIndex, y) in rowsA.enumerated() {
            for (columnIndex, x) in columnsA.enumerated() {
                parts.append(part(.generateBox(width: 0.0018, height: 0.0022, depth: 0.0005),
                                  windowMaterial(row: rowIndex, column: columnIndex),
                                  at: [x, y, 0.0047]))
            }
        }
        // タワーBの窓(2列×3段)
        let rowsB: [Float] = [0.0045, 0.0105, 0.0165]
        let columnsB: [Float] = [0.0040, 0.0070]
        for (rowIndex, y) in rowsB.enumerated() {
            for (columnIndex, x) in columnsB.enumerated() {
                parts.append(part(.generateBox(width: 0.0014, height: 0.0018, depth: 0.0005),
                                  windowMaterial(row: rowIndex, column: columnIndex + 1),
                                  at: [x, y, 0.0050]))
            }
        }
        // 屋上アンテナ+航空障害灯
        parts.append(part(.generateCylinder(height: 0.0042, radius: 0.0004),
                          matte("#33302E"),
                          at: [-0.0040, 0.0321, 0]))
        parts.append(part(.generateSphere(radius: 0.0008),
                          glow("#FF5A5A", night: night),
                          at: [-0.0040, 0.0346, 0]))
        return group(parts)
    }

    // MARK: - ちゃぶ台

    /// 木の円板+短い脚+湯のみ
    private static func makeTable() -> Entity {
        var parts: [Entity] = []
        // 天板
        parts.append(part(.generateCylinder(height: 0.0016, radius: 0.0085),
                          shiny("#C89B6C", roughness: 0.5),
                          at: [0, 0.0092, 0]))
        // 脚(4本)
        let legMaterial = matte("#8A5A33")
        for x in [Float(-0.0039), 0.0039] {
            for z in [Float(-0.0039), 0.0039] {
                parts.append(part(.generateCylinder(height: 0.0085, radius: 0.0007),
                                  legMaterial,
                                  at: [x, 0.00425, z]))
            }
        }
        // 湯のみ+お茶
        parts.append(part(.generateCylinder(height: 0.0014, radius: 0.0012),
                          matte("#F6F2E7", roughness: 0.5),
                          at: [0.0020, 0.0107, 0.0010]))
        parts.append(part(.generateCylinder(height: 0.0003, radius: 0.0009),
                          shiny("#7FA85A", roughness: 0.25),
                          at: [0.0020, 0.01155, 0.0010]))
        return group(parts)
    }

    // MARK: - 料理

    /// 白いお皿+おにぎり・玉子焼き・ミニトマト・ブロッコリー
    private static func makeFood() -> Entity {
        var parts: [Entity] = []
        // お皿
        parts.append(part(.generateCylinder(height: 0.0010, radius: 0.0065),
                          shiny("#F8F5EF", roughness: 0.3),
                          at: [0, 0.0005, 0]))
        // おにぎり(白)+のり
        parts.append(part(.generateSphere(radius: 0.0022),
                          matte("#FBFBF6", roughness: 0.9),
                          at: [-0.0022, 0.0030, 0.0004],
                          scaled: [1.0, 0.9, 0.8]))
        parts.append(part(.generateBox(width: 0.0018, height: 0.0013, depth: 0.0004),
                          matte("#26301E", roughness: 0.8),
                          at: [-0.0022, 0.0018, 0.0022]))
        // 玉子焼き
        parts.append(part(.generateBox(width: 0.0023, height: 0.0014, depth: 0.0015, cornerRadius: 0.0004),
                          matte("#F8C64A", roughness: 0.7),
                          at: [0.0023, 0.0022, -0.0014]))
        // ミニトマト
        parts.append(part(.generateSphere(radius: 0.0011),
                          shiny("#E8483F", roughness: 0.25),
                          at: [0.0019, 0.0021, 0.0021]))
        // ブロッコリー
        parts.append(part(.generateSphere(radius: 0.0013),
                          matte("#4E9B4F", roughness: 1.0),
                          at: [-0.0002, 0.0023, 0.0026]))
        return group(parts)
    }

    // MARK: - 木

    /// 幹+緑の球3つ
    private static func makeTree(night: Bool) -> Entity {
        var parts: [Entity] = []
        parts.append(part(.generateCylinder(height: 0.013, radius: 0.0016),
                          matte("#8A5A33"),
                          at: [0, 0.0065, 0]))
        let leafA = matte(night ? "#2F5E36" : "#4E9B4F", roughness: 1.0)
        let leafB = matte(night ? "#28522F" : "#3E8B41", roughness: 1.0)
        parts.append(part(.generateSphere(radius: 0.0075), leafA, at: [0, 0.0170, 0]))
        parts.append(part(.generateSphere(radius: 0.0055), leafB, at: [-0.0040, 0.0135, 0.0010]))
        parts.append(part(.generateSphere(radius: 0.0052), leafB, at: [0.0042, 0.0140, -0.0010]))
        return group(parts)
    }

    // MARK: - ベンチ

    /// 木の座板+背もたれ+脚
    private static func makeBench() -> Entity {
        var parts: [Entity] = []
        // 座板
        parts.append(part(.generateBox(width: 0.016, height: 0.0014, depth: 0.0048, cornerRadius: 0.0005),
                          matte("#C89B6C", roughness: 0.7),
                          at: [0, 0.0055, 0]))
        // 背もたれ(少し後ろへ傾ける)
        parts.append(part(.generateBox(width: 0.016, height: 0.0042, depth: 0.0012, cornerRadius: 0.0005),
                          matte("#B98B5C", roughness: 0.7),
                          at: [0, 0.0085, -0.0028],
                          rotated: simd_quatf(angle: -0.18, axis: [1, 0, 0])))
        // 脚(4本)
        let legMaterial = matte("#3E6E5A", roughness: 0.6)
        for x in [Float(-0.0060), 0.0060] {
            for z in [Float(-0.0015), 0.0015] {
                parts.append(part(.generateBox(width: 0.0012, height: 0.0050, depth: 0.0012),
                                  legMaterial,
                                  at: [x, 0.0025, z]))
            }
        }
        return group(parts)
    }

    // MARK: - 街灯

    /// 柱+発光する球(夜は明るく)
    private static func makeStreetLight(night: Bool) -> Entity {
        var parts: [Entity] = []
        // 台座
        parts.append(part(.generateCylinder(height: 0.0010, radius: 0.0018),
                          matte("#33383F"),
                          at: [0, 0.0005, 0]))
        // 柱
        parts.append(part(.generateCylinder(height: 0.028, radius: 0.0007),
                          matte("#3B4048", roughness: 0.6),
                          at: [0, 0.0150, 0]))
        // 灯具の受け
        parts.append(part(.generateCylinder(height: 0.0008, radius: 0.0012),
                          matte("#33383F"),
                          at: [0, 0.0288, 0]))
        // 発光球
        parts.append(part(.generateSphere(radius: 0.0026),
                          glow(night ? "#FFE9A8" : "#F2EEDE", night: night),
                          at: [0, 0.0306, 0]))
        return group(parts)
    }

    // MARK: - プール

    /// 水色の角丸プール+白い縁+はしご+小さな浮き輪
    private static func makePool() -> Entity {
        var parts: [Entity] = []
        // 縁(デッキ)
        parts.append(part(.generateBox(width: 0.026, height: 0.0036, depth: 0.019, cornerRadius: 0.0032),
                          matte("#E8E3D5", roughness: 0.6),
                          at: [0, 0.0018, 0]))
        // 水(半透明)
        parts.append(part(.generateBox(width: 0.0225, height: 0.0030, depth: 0.0155, cornerRadius: 0.0028),
                          translucent("#46C2E0", opacity: 0.78, roughness: 0.1),
                          at: [0, 0.0020, 0]))
        // はしご(白い2本)
        for z in [Float(0.0016), 0.0042] {
            parts.append(part(.generateCylinder(height: 0.0040, radius: 0.0003),
                              matte("#FBFBF8", roughness: 0.4),
                              at: [0.0105, 0.0044, z]))
        }
        // 水面に浮かぶ小さな浮き輪
        parts.append(part(.generateCylinder(height: 0.0010, radius: 0.0022),
                          matte("#FFD34D", roughness: 0.6),
                          at: [-0.0045, 0.0038, 0.0025]))
        return group(parts)
    }

    // MARK: - 浮き輪

    /// トーラスの代わりに二重の円筒で輪を表現
    private static func makeFloatRing() -> Entity {
        var parts: [Entity] = []
        // 外側の輪(ピンク)
        parts.append(part(.generateCylinder(height: 0.0030, radius: 0.0075),
                          shiny("#FF7FA0", roughness: 0.35),
                          at: [0, 0.0015, 0]))
        // 内側のくぼみ(淡色で穴に見せる)
        parts.append(part(.generateCylinder(height: 0.0026, radius: 0.0040),
                          matte("#EAF2F5", roughness: 0.8),
                          at: [0, 0.0013, 0]))
        // 白い縞(上面に4枚)
        for index in 0..<4 {
            let angle = Float(index) / 4 * 2 * .pi
            let position: SIMD3<Float> = [cosf(angle) * 0.0056, 0.0030, sinf(angle) * 0.0056]
            parts.append(part(.generateBox(width: 0.0034, height: 0.0006, depth: 0.0026, cornerRadius: 0.0002),
                              matte("#FBFBF8", roughness: 0.5),
                              at: position,
                              rotated: simd_quatf(angle: -angle, axis: [0, 1, 0])))
        }
        return group(parts)
    }

    // MARK: - テント

    /// 傾いた板2枚のA型テント+ポール+入口+旗
    private static func makeTent() -> Entity {
        var parts: [Entity] = []
        // 左右の幕(60度に立てかける)
        parts.append(part(.generateBox(width: 0.016, height: 0.0012, depth: 0.018),
                          matte("#FF8A5C", roughness: 0.8),
                          at: [0.00375, 0.0065, 0],
                          rotated: simd_quatf(angle: -1.047, axis: [0, 0, 1])))
        parts.append(part(.generateBox(width: 0.016, height: 0.0012, depth: 0.018),
                          matte("#F0794F", roughness: 0.8),
                          at: [-0.00375, 0.0065, 0],
                          rotated: simd_quatf(angle: 1.047, axis: [0, 0, 1])))
        // 棟のポール(奥行き方向)
        parts.append(part(.generateCylinder(height: 0.019, radius: 0.0005),
                          matte("#8A5A33"),
                          at: [0, 0.0132, 0],
                          rotated: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
        // 入口(正面の暗い三角 = つぶした円錐)
        parts.append(part(.generateCone(height: 0.0058, radius: 0.0032),
                          matte("#4A3B33", roughness: 1.0),
                          at: [0, 0.0029, 0.0090],
                          scaled: [1.0, 1.0, 0.15]))
        // 旗
        parts.append(part(.generateCylinder(height: 0.0035, radius: 0.0003),
                          matte("#8A5A33"),
                          at: [0, 0.01495, 0.0090]))
        parts.append(part(.generateBox(width: 0.0022, height: 0.0012, depth: 0.0003),
                          matte("#FFD34D", roughness: 0.6),
                          at: [0.0013, 0.0161, 0.0090]))
        return group(parts)
    }

    // MARK: - 焚き火

    /// 薪+石+橙色に発光する炎
    private static func makeCampfire(night: Bool) -> Entity {
        var parts: [Entity] = []
        // 薪(3本を放射状に寝かせる)
        let logMaterial = matte("#7A5230", roughness: 0.9)
        let layFlat = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        for yaw in [Float(0.20), 1.25, 2.35] {
            let turn = simd_quatf(angle: yaw, axis: [0, 1, 0])
            parts.append(part(.generateCylinder(height: 0.011, radius: 0.0013),
                              logMaterial,
                              at: [0, 0.0013, 0],
                              rotated: turn * layFlat))
        }
        // 囲いの石
        let stoneMaterial = matte("#9AA0A6", roughness: 1.0)
        for index in 0..<5 {
            let angle = Float(index) / 5 * 2 * .pi + 0.4
            parts.append(part(.generateSphere(radius: 0.0012),
                              stoneMaterial,
                              at: [cosf(angle) * 0.0062, 0.0009, sinf(angle) * 0.0062],
                              scaled: [1.0, 0.7, 1.0]))
        }
        // 炎(外側の橙+内側の黄)
        parts.append(part(.generateCone(height: 0.0105, radius: 0.0038),
                          glow("#FF7A2F", night: night),
                          at: [0, 0.00785, 0]))
        parts.append(part(.generateCone(height: 0.0068, radius: 0.0022),
                          glow("#FFD34D", night: night),
                          at: [0, 0.0060, 0.0002]))
        // 熾火
        parts.append(part(.generateSphere(radius: 0.0008),
                          glow("#FF4E2A", night: night),
                          at: [0.0016, 0.0016, 0.0012]))
        return group(parts)
    }

    // MARK: - ヤシの木

    /// 曲がった幹(円筒を少しずつ傾けて積む)+放射状の葉+ココナッツ
    private static func makePalmTree() -> Entity {
        var parts: [Entity] = []
        let trunkHexes = ["#8A5A33", "#96653C"]
        let segmentHeight: Float = 0.0068
        let tilts: [Float] = [0.05, 0.13, 0.21, 0.30, 0.40]
        var basePoint: SIMD3<Float> = .zero
        var topPoint: SIMD3<Float> = .zero
        for (index, tilt) in tilts.enumerated() {
            let rotation = simd_quatf(angle: -tilt, axis: [0, 0, 1])
            let direction = rotation.act([0, 1, 0])
            let center = basePoint + direction * (segmentHeight / 2)
            parts.append(part(.generateCylinder(height: segmentHeight,
                                                radius: 0.0015 - Float(index) * 0.00012),
                              matte(trunkHexes[index % 2], roughness: 0.9),
                              at: center,
                              rotated: rotation))
            basePoint += direction * (segmentHeight * 0.94)
            topPoint = basePoint
        }
        // 葉(6枚を放射状に、先端を垂らす)
        let leafHexes = ["#3E8B41", "#57A85C"]
        for index in 0..<6 {
            let yaw = Float(index) / 6 * 2 * .pi + 0.3
            let droop = simd_quatf(angle: -0.62, axis: [0, 0, 1])
            let turn = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let leafOrientation = turn * droop
            let offset = leafOrientation.act([0.0062, 0, 0])
            parts.append(part(.generateBox(width: 0.0118, height: 0.0006, depth: 0.0030, cornerRadius: 0.0003),
                              matte(leafHexes[index % 2], roughness: 0.9),
                              at: topPoint + offset,
                              rotated: leafOrientation))
        }
        // ココナッツ
        parts.append(part(.generateSphere(radius: 0.0013),
                          matte("#7A5230"),
                          at: topPoint + SIMD3<Float>(-0.0012, -0.0015, 0.0009)))
        parts.append(part(.generateSphere(radius: 0.0012),
                          matte("#8A5F3B"),
                          at: topPoint + SIMD3<Float>(0.0004, -0.0017, -0.0011)))
        return group(parts)
    }

    // MARK: - 小舟

    /// 角丸の船体+舳先の円錐+マスト+帆+旗
    private static func makeBoat() -> Entity {
        var parts: [Entity] = []
        let hullMaterial = shiny("#A9744A", roughness: 0.55)
        // 船体
        parts.append(part(.generateBox(width: 0.018, height: 0.0042, depth: 0.0075, cornerRadius: 0.0018),
                          hullMaterial,
                          at: [0, 0.0021, 0]))
        // 舷縁(上のふち)
        parts.append(part(.generateBox(width: 0.0185, height: 0.0009, depth: 0.0080, cornerRadius: 0.0020),
                          matte("#7A5230", roughness: 0.7),
                          at: [0, 0.0043, 0]))
        // 舳先(円錐を横倒しにしてすぼめる)
        parts.append(part(.generateCone(height: 0.0050, radius: 0.0032),
                          hullMaterial,
                          at: [0.0115, 0.0021, 0],
                          rotated: simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]),
                          scaled: [0.62, 1.0, 0.85]))
        // マスト
        parts.append(part(.generateCylinder(height: 0.016, radius: 0.0006),
                          matte("#8A5A33"),
                          at: [-0.0020, 0.0122, 0]))
        // 帆
        parts.append(part(.generateBox(width: 0.0060, height: 0.0090, depth: 0.0005, cornerRadius: 0.0004),
                          matte("#F6F2E7", roughness: 0.85),
                          at: [0.0015, 0.0125, 0]))
        // 旗
        parts.append(part(.generateBox(width: 0.0024, height: 0.0011, depth: 0.0004),
                          matte("#E0453A", roughness: 0.6),
                          at: [-0.0006, 0.0196, 0]))
        return group(parts)
    }

    // MARK: - 貝殻

    /// つぶした球の小さな扇+すじ+ちょうつがい
    private static func makeShell() -> Entity {
        var parts: [Entity] = []
        // 本体(つぶした球)
        parts.append(part(.generateSphere(radius: 0.0042),
                          shiny("#F5D9CE", roughness: 0.35),
                          at: [0, 0.0019, 0],
                          scaled: [1.15, 0.45, 0.95]))
        // 放射状のすじ(薄い扇状の膨らみ)
        for yaw in [Float(-0.35), 0, 0.35] {
            parts.append(part(.generateSphere(radius: 0.00425),
                              shiny("#FDEDE6", roughness: 0.4),
                              at: [0, 0.00195, 0],
                              rotated: simd_quatf(angle: yaw, axis: [0, 1, 0]),
                              scaled: [0.07, 0.46, 0.96]))
        }
        // ちょうつがい(付け根)
        parts.append(part(.generateSphere(radius: 0.0015),
                          matte("#E3B39A", roughness: 0.6),
                          at: [0, 0.0013, -0.0034],
                          scaled: [0.9, 0.62, 0.8]))
        return group(parts)
    }

    // MARK: - 芝生

    /// 緑の小さな円錐の束+小花
    private static func makeGrass() -> Entity {
        var parts: [Entity] = []
        // (足元位置, 高さ, 向き, 傾き, 色)
        let blades: [(SIMD3<Float>, Float, Float, Float, String)] = [
            ([ 0.0000, 0,  0.0000], 0.0078, 0.0, 0.00, "#3E8B41"),
            ([ 0.0021, 0,  0.0009], 0.0060, 0.9, 0.18, "#57A85C"),
            ([-0.0019, 0,  0.0012], 0.0064, 2.1, 0.16, "#6FBF6A"),
            ([ 0.0011, 0, -0.0021], 0.0055, 3.4, 0.20, "#57A85C"),
            ([-0.0014, 0, -0.0016], 0.0068, 4.4, 0.14, "#3E8B41"),
            ([ 0.0028, 0, -0.0006], 0.0048, 5.2, 0.22, "#6FBF6A"),
            ([-0.0028, 0, -0.0002], 0.0050, 1.6, 0.24, "#57A85C"),
        ]
        for (foot, height, yaw, tilt, hex) in blades {
            let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: tilt, axis: [0, 0, 1])
            let center = foot + orientation.act([0, height / 2, 0])
            parts.append(part(.generateCone(height: height, radius: 0.00085),
                              matte(hex, roughness: 1.0),
                              at: center,
                              rotated: orientation))
        }
        // 小さな白い花
        parts.append(part(.generateSphere(radius: 0.00065),
                          matte("#FBFBF8", roughness: 0.8),
                          at: [0.0024, 0.0064, 0.0011]))
        parts.append(part(.generateSphere(radius: 0.00035),
                          matte("#FFD34D", roughness: 0.7),
                          at: [0.0024, 0.0069, 0.0011]))
        return group(parts)
    }
}
