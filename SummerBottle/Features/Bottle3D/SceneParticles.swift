//
//  SceneParticles.swift
//  SummerBottle
//
//  瓶の中を漂うパーティクル(常時弱い ambient)と、シェイク時のバーストの
//  ParticleEmitterComponent を ParticleKind ごとに組み立てる。
//

import Foundation
import UIKit
import RealityKit

@MainActor
enum SceneParticles {

    /// config.particle が .none のときに使う、シーンに合った既定のパーティクル
    static func defaultKind(for config: SceneConfig) -> ParticleKind {
        if config.objects.contains(where: { $0.type == .fireworks }) { return .sparks }
        if config.objects.contains(where: { $0.type == .lanternString || $0.type == .stall }) { return .sparks }
        if config.timeOfDay == .night { return .fireflies }
        if config.hasSea { return .splash }
        if config.sandAmount > 0.5 { return .sand }
        return .bubbles
    }

    /// 常時漂う弱い放出。kind が .none なら nil。
    /// radius/height は内容物領域の寸法(メートル)。
    static func ambientComponent(kind: ParticleKind, radius: Float, height: Float) -> ParticleEmitterComponent? {
        guard kind != .none else { return nil }
        var component = baseComponent(radius: radius, height: height)
        configure(kind: kind, component: &component, radius: radius)
        return component
    }

    /// シェイク時のバースト(高い birthRate で短時間放出する。停止・削除は呼び出し側が行う)
    static func burstComponent(kind: ParticleKind, radius: Float, height: Float) -> ParticleEmitterComponent {
        let effective = kind == .none ? ParticleKind.bubbles : kind
        var component = baseComponent(radius: radius, height: height)
        configure(kind: effective, component: &component, radius: radius)
        component.mainEmitter.birthRate *= 22
        component.mainEmitter.birthRateVariation *= 10
        component.speed *= 2.2
        component.mainEmitter.lifeSpan = max(component.mainEmitter.lifeSpan * 0.7, 0.6)
        return component
    }

    // MARK: - 共通の土台

    private static func baseComponent(radius: Float, height: Float) -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()
        component.emitterShape = .box
        component.emitterShapeSize = SIMD3<Float>(radius * 1.3, height * 0.8, radius * 1.3)
        component.birthLocation = .volume
        component.isEmitting = true
        return component
    }

    // MARK: - 種類別の見た目

    private static func configure(kind: ParticleKind, component: inout ParticleEmitterComponent, radius: Float) {
        switch kind {
        case .none:
            component.mainEmitter.birthRate = 0

        case .splash:
            // 水しぶき: 白〜水色の小粒が跳ねて落ちる
            component.speed = 0.045
            component.speedVariation = 0.03
            component.mainEmitter.birthRate = 26
            component.mainEmitter.birthRateVariation = 8
            component.mainEmitter.lifeSpan = 1.1
            component.mainEmitter.lifeSpanVariation = 0.4
            component.mainEmitter.size = 0.0016
            component.mainEmitter.sizeVariation = 0.0008
            component.mainEmitter.acceleration = SIMD3<Float>(0, -0.09, 0)
            component.mainEmitter.color = .evolving(
                start: .single(UIColor(hex: "#FFFFFF")),
                end: .single(UIColor(hex: "#9FD8EF"))
            )
            component.mainEmitter.opacityCurve = .linearFadeOut

        case .sand:
            // 砂粒: 砂色の細かい粒がゆっくり舞って沈む
            component.speed = 0.012
            component.speedVariation = 0.01
            component.mainEmitter.birthRate = 24
            component.mainEmitter.birthRateVariation = 6
            component.mainEmitter.lifeSpan = 1.6
            component.mainEmitter.lifeSpanVariation = 0.6
            component.mainEmitter.size = 0.0011
            component.mainEmitter.sizeVariation = 0.0005
            component.mainEmitter.acceleration = SIMD3<Float>(0, -0.03, 0)
            component.mainEmitter.color = .constant(
                .random(a: UIColor(hex: "#F5E6C8"), b: UIColor(hex: "#E0C89A"))
            )
            component.mainEmitter.opacityCurve = .linearFadeOut

        case .sparks:
            // 花火の光: 橙〜赤の速い粒
            component.speed = 0.11
            component.speedVariation = 0.06
            component.mainEmitter.birthRate = 18
            component.mainEmitter.birthRateVariation = 6
            component.mainEmitter.lifeSpan = 0.85
            component.mainEmitter.lifeSpanVariation = 0.3
            component.mainEmitter.size = 0.0017
            component.mainEmitter.sizeVariation = 0.0008
            component.mainEmitter.acceleration = SIMD3<Float>(0, -0.05, 0)
            component.mainEmitter.color = .evolving(
                start: .random(a: UIColor(hex: "#FFE28A"), b: UIColor(hex: "#FF9838")),
                end: .single(UIColor(hex: "#E0453A"))
            )
            component.mainEmitter.opacityCurve = .linearFadeOut

        case .fireflies:
            // 蛍: 黄緑の光が少数、ゆっくり漂う
            component.speed = 0.013
            component.speedVariation = 0.01
            component.mainEmitter.birthRate = 6
            component.mainEmitter.birthRateVariation = 2
            component.mainEmitter.lifeSpan = 3.2
            component.mainEmitter.lifeSpanVariation = 1.2
            component.mainEmitter.size = 0.0021
            component.mainEmitter.sizeVariation = 0.0007
            component.mainEmitter.acceleration = SIMD3<Float>(0, 0.004, 0)
            component.mainEmitter.color = .evolving(
                start: .single(UIColor(hex: "#D8F58A")),
                end: .single(UIColor(hex: "#8FCB5A"))
            )
            component.mainEmitter.opacityCurve = .quickFadeInOut

        case .stars:
            // 星: 白い小さな瞬き
            component.speed = 0.004
            component.speedVariation = 0.004
            component.mainEmitter.birthRate = 9
            component.mainEmitter.birthRateVariation = 3
            component.mainEmitter.lifeSpan = 2.4
            component.mainEmitter.lifeSpanVariation = 0.9
            component.mainEmitter.size = 0.0014
            component.mainEmitter.sizeVariation = 0.0006
            component.mainEmitter.acceleration = .zero
            component.mainEmitter.color = .constant(
                .random(a: UIColor(hex: "#FFFFFF"), b: UIColor(hex: "#FFEFC2"))
            )
            component.mainEmitter.opacityCurve = .quickFadeInOut

        case .petals:
            // 花びら: 桃色がひらひら落ちる
            component.speed = 0.02
            component.speedVariation = 0.014
            component.mainEmitter.birthRate = 10
            component.mainEmitter.birthRateVariation = 4
            component.mainEmitter.lifeSpan = 2.8
            component.mainEmitter.lifeSpanVariation = 0.8
            component.mainEmitter.size = 0.0024
            component.mainEmitter.sizeVariation = 0.0009
            component.mainEmitter.acceleration = SIMD3<Float>(0.008, -0.016, 0)
            component.mainEmitter.color = .evolving(
                start: .single(UIColor(hex: "#FFC7D9")),
                end: .single(UIColor(hex: "#FF8FB0"))
            )
            component.mainEmitter.opacityCurve = .linearFadeOut

        case .bubbles:
            // シャボン玉: 淡い水色がゆっくり上る
            component.speed = 0.028
            component.speedVariation = 0.015
            component.mainEmitter.birthRate = 12
            component.mainEmitter.birthRateVariation = 4
            component.mainEmitter.lifeSpan = 2.2
            component.mainEmitter.lifeSpanVariation = 0.7
            component.mainEmitter.size = 0.0020
            component.mainEmitter.sizeVariation = 0.0010
            component.mainEmitter.acceleration = SIMD3<Float>(0, 0.02, 0)
            component.mainEmitter.color = .evolving(
                start: .single(UIColor(hex: "#E8FBFF")),
                end: .single(UIColor(hex: "#A5DCEB"))
            )
            component.mainEmitter.opacityCurve = .linearFadeOut
        }
    }
}
