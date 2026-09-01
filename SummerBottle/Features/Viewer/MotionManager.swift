//
//  MotionManager.swift
//  SummerBottle
//
//  3D鑑賞用のモーション管理。
//  deviceMotion(60Hz)の pitch/roll を onUpdate へ流し、
//  userAcceleration のスパイク2回でシェイクを検出する。
//

import CoreMotion
import Foundation
import Observation

@MainActor
@Observable
final class MotionManager {
    /// 端末の傾き(pitch/roll、ラジアン)を毎フレーム受け取るコールバック
    @ObservationIgnored var onUpdate: ((_ pitch: Float, _ roll: Float) -> Void)?
    /// シェイク検出時のコールバック
    @ObservationIgnored var onShake: (() -> Void)?

    /// 実機でデバイスモーションが使えるか(シミュレータでは false)
    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    private(set) var isRunning = false

    @ObservationIgnored private let motionManager = CMMotionManager()

    // シェイク判定の内部状態
    @ObservationIgnored private var wasAboveThreshold = false
    @ObservationIgnored private var spikeTimes: [Date] = []
    @ObservationIgnored private var lastShakeAt: Date = .distantPast

    /// userAcceleration のノルムがこの値を超えたらスパイクとみなす
    private static let accelerationThreshold: Double = 1.3
    /// この時間内にスパイクが2回でシェイク判定
    private static let spikeWindow: TimeInterval = 0.8
    /// シェイク判定後のデバウンス
    private static let shakeDebounce: TimeInterval = 1.5

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !isRunning else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] deviceMotion, _ in
            guard let deviceMotion else { return }
            let pitch = Float(deviceMotion.attitude.pitch)
            let roll = Float(deviceMotion.attitude.roll)
            let a = deviceMotion.userAcceleration
            let norm = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            // ハンドラはメインキューで呼ばれる
            MainActor.assumeIsolated {
                self?.process(pitch: pitch, roll: roll, accelerationNorm: norm)
            }
        }
        isRunning = true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        wasAboveThreshold = false
        spikeTimes.removeAll()
    }

    // MARK: - 内部処理

    private func process(pitch: Float, roll: Float, accelerationNorm: Double) {
        onUpdate?(pitch, roll)

        // 閾値を下から上へ横切った瞬間だけを「スパイク」として数える
        if accelerationNorm > Self.accelerationThreshold {
            if !wasAboveThreshold {
                wasAboveThreshold = true
                registerSpike(at: Date())
            }
        } else {
            wasAboveThreshold = false
        }
    }

    private func registerSpike(at now: Date) {
        guard now.timeIntervalSince(lastShakeAt) > Self.shakeDebounce else { return }
        spikeTimes.removeAll { now.timeIntervalSince($0) > Self.spikeWindow }
        spikeTimes.append(now)
        if spikeTimes.count >= 2 {
            spikeTimes.removeAll()
            lastShakeAt = now
            onShake?()
        }
    }
}
