//
//  BottleGeometry.swift
//  SummerBottle
//
//  BottleType ごとの瓶の寸法と、ガラス本体・コルク栓のエンティティ生成。
//  座標系: 原点 = 瓶の底面中心、+Y が上(メートル)。
//  ガラスは透過マテリアルのため、内容物より「後」にシーンへ追加すること
//  (追加順は BottleSceneController が管理する)。
//

import Foundation
import UIKit
import RealityKit
import simd

/// 瓶1種類分の寸法セットとガラス・コルクの生成器
struct BottleGeometry {
    let type: BottleType

    /// 胴の半径(round は球の半径)
    let bodyRadius: Float
    /// 胴の高さ(round は球の直径)
    let bodyHeight: Float
    /// 肩(胴から首への絞り)の高さ
    let shoulderHeight: Float
    let neckRadius: Float
    let neckHeight: Float

    /// 内容物を置ける領域(SceneObject の正規化座標のマッピング先)
    let contentRadius: Float
    let contentBaseY: Float
    let contentHeight: Float

    /// round(球形)か
    let isSpherical: Bool

    // MARK: - 派生値

    /// 瓶全高(コルクは含まない)。カメラ距離の目安。
    var totalHeight: Float { bodyHeight + shoulderHeight + neckHeight }
    var neckBaseY: Float { bodyHeight + shoulderHeight }
    var neckTopY: Float { totalHeight }

    var corkRadius: Float { neckRadius * 1.22 }
    var corkHeight: Float { max(neckRadius * 2.1, 0.018) }
    /// コルクが瓶口に差し込まれている深さ
    var corkInset: Float { corkHeight * 0.42 }

    /// ミニチュアの大きさ補正(standard の内容半径を 1 とする)
    var miniatureScale: Float { contentRadius / 0.0473 }

    // MARK: - 種類別の寸法

    static func geometry(for type: BottleType) -> BottleGeometry {
        switch type {
        case .standard:
            // 円筒+首。全高約 0.24
            return BottleGeometry(
                type: type,
                bodyRadius: 0.055, bodyHeight: 0.165,
                shoulderHeight: 0.030, neckRadius: 0.020, neckHeight: 0.045,
                contentRadius: 0.0473, contentBaseY: 0.006, contentHeight: 0.145,
                isSpherical: false
            )
        case .round:
            // 球体+短い首。広い風景向け
            return BottleGeometry(
                type: type,
                bodyRadius: 0.072, bodyHeight: 0.144,
                shoulderHeight: 0.012, neckRadius: 0.018, neckHeight: 0.034,
                contentRadius: 0.0450, contentBaseY: 0.018, contentHeight: 0.100,
                isSpherical: true
            )
        case .mini:
            // 小さな円筒
            return BottleGeometry(
                type: type,
                bodyRadius: 0.036, bodyHeight: 0.100,
                shoulderHeight: 0.020, neckRadius: 0.014, neckHeight: 0.030,
                contentRadius: 0.0310, contentBaseY: 0.005, contentHeight: 0.088,
                isSpherical: false
            )
        case .lantern:
            // 少し太めの円筒。内部が発光する(光は BottleSceneController が足す)
            return BottleGeometry(
                type: type,
                bodyRadius: 0.062, bodyHeight: 0.150,
                shoulderHeight: 0.026, neckRadius: 0.022, neckHeight: 0.044,
                contentRadius: 0.0533, contentBaseY: 0.006, contentHeight: 0.132,
                isSpherical: false
            )
        case .drift:
            // 漂流瓶。コルク+古紙ラベル(ラベルは BottleSceneController が貼る)
            return BottleGeometry(
                type: type,
                bodyRadius: 0.052, bodyHeight: 0.158,
                shoulderHeight: 0.032, neckRadius: 0.019, neckHeight: 0.045,
                contentRadius: 0.0447, contentBaseY: 0.006, contentHeight: 0.139,
                isSpherical: false
            )
        case .soda:
            // 細長いラムネ瓶+首のビー玉
            return BottleGeometry(
                type: type,
                bodyRadius: 0.040, bodyHeight: 0.190,
                shoulderHeight: 0.026, neckRadius: 0.015, neckHeight: 0.044,
                contentRadius: 0.0344, contentBaseY: 0.005, contentHeight: 0.150,
                isSpherical: false
            )
        }
    }

    // MARK: - ガラス

    /// ガラス本体(胴・肩・首・口・底)。Collision/InputTarget は付けない。
    func makeGlassEntity() -> Entity {
        let root = Entity()
        root.name = "bottleGlass"

        let wall = Self.glassMaterial(tintHex: glassTintHex, opacity: 0.15)
        let thick = Self.glassMaterial(tintHex: glassTintHex, opacity: 0.30)

        // ラムネ瓶のビー玉(半透明ガラスより先に足して見えやすくする)
        if type == .soda {
            let marble = ModelEntity(
                mesh: .generateSphere(radius: neckRadius * 0.82),
                materials: [Self.shinyMaterial(hex: "#7EC8E3", roughness: 0.08)]
            )
            marble.position = SIMD3<Float>(0, neckBaseY + neckRadius * 0.9, 0)
            root.addChild(marble)
        }

        // 底(少し濃いガラス)
        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: isSpherical ? bodyRadius * 0.45 : bodyRadius),
            materials: [thick]
        )
        base.position = SIMD3<Float>(0, 0.002, 0)
        root.addChild(base)

        if isSpherical {
            // 球の胴
            let body = ModelEntity(
                mesh: .generateSphere(radius: bodyRadius),
                materials: [wall]
            )
            body.position = SIMD3<Float>(0, bodyHeight / 2, 0)
            root.addChild(body)
        } else {
            // 円筒の胴
            let body = ModelEntity(
                mesh: .generateCylinder(height: bodyHeight, radius: bodyRadius),
                materials: [wall]
            )
            body.position = SIMD3<Float>(0, bodyHeight / 2, 0)
            root.addChild(body)
        }

        // 肩(胴→首の絞り)。胴の上面へ少し沈めて継ぎ目の帯を消す
        let shoulder = ModelEntity(
            mesh: .generateCone(height: shoulderHeight, radius: isSpherical ? neckRadius * 1.9 : bodyRadius * 0.98),
            materials: [wall]
        )
        shoulder.position = SIMD3<Float>(0, bodyHeight - 0.003 + shoulderHeight / 2, 0)
        root.addChild(shoulder)

        // 首。円錐の先端(半径0)と首(半径neckRadius)が点接続で浮いて見えないよう、
        // 肩の中(円錐の半径が neckRadius になる高さ)まで首を下へ伸ばして重ねる
        let neckExtend = shoulderHeight * 0.55
        let neck = ModelEntity(
            mesh: .generateCylinder(height: neckHeight + neckExtend, radius: neckRadius),
            materials: [wall]
        )
        neck.position = SIMD3<Float>(0, neckBaseY - neckExtend + (neckHeight + neckExtend) / 2, 0)
        root.addChild(neck)

        // 口(リップ)
        let lip = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: neckRadius * 1.22),
            materials: [thick]
        )
        lip.position = SIMD3<Float>(0, neckTopY - 0.0025, 0)
        root.addChild(lip)

        return root
    }

    // MARK: - コルク栓

    /// コルク栓。原点 = 瓶口の高さ(neckTopY)に置く親(pivot)からの相対で、
    /// 閉じた状態では少し瓶口に差し込まれている。
    func makeCorkEntity() -> Entity {
        let root = Entity()
        root.name = "bottleCork"

        let corkHex: String
        let capHex: String
        switch type {
        case .drift:
            corkHex = "#A87E4E"
            capHex = "#8F6A40"
        case .soda:
            corkHex = "#7FBF9F"
            capHex = "#5FA684"
        default:
            corkHex = "#C99B63"
            capHex = "#B0844F"
        }

        // 本体(下端が瓶口へ少し差し込まれる)
        let body = ModelEntity(
            mesh: .generateCylinder(height: corkHeight, radius: corkRadius),
            materials: [Self.matteMaterial(hex: corkHex, roughness: 0.9)]
        )
        body.position = SIMD3<Float>(0, corkHeight / 2 - corkInset, 0)
        root.addChild(body)

        // 上面のふち(少し広いキャップ)
        let cap = ModelEntity(
            mesh: .generateCylinder(height: 0.0035, radius: corkRadius * 1.12),
            materials: [Self.matteMaterial(hex: capHex, roughness: 0.85)]
        )
        cap.position = SIMD3<Float>(0, corkHeight - corkInset - 0.00175, 0)
        root.addChild(cap)

        return root
    }

    // MARK: - マテリアル

    private var glassTintHex: String {
        switch type {
        case .soda: "#AEE3D8"
        case .drift: "#D3DEC2"
        case .lantern: "#EBE0C8"
        default: "#C6E7EC"
        }
    }

    static func glassMaterial(tintHex: String, opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: tintHex))
        material.roughness = .init(floatLiteral: 0.05)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    static func matteMaterial(hex: String, roughness: Float = 0.85) -> SimpleMaterial {
        SimpleMaterial(
            color: UIColor(hex: hex),
            roughness: MaterialScalarParameter(floatLiteral: roughness),
            isMetallic: false
        )
    }

    static func shinyMaterial(hex: String, roughness: Float = 0.3) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0.0)
        return material
    }

    static func translucentMaterial(hex: String, opacity: Float, roughness: Float = 0.15) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }
}
