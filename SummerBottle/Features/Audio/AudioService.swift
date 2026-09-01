//
//  AudioService.swift
//  SummerBottle
//
//  環境音・録音音声の再生を一元管理するサービス。
//  プリセットは PresetSoundscapes が合成したWAVを、録音はファイルURLを再生する。
//

import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AudioService {
    static let shared = AudioService()

    private(set) var isPlaying: Bool = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var finishWatcher: Task<Void, Never>?

    private init() {}

    /// プリセット環境音を再生する。silence の場合は停止のみ。
    func playPreset(_ kind: SoundscapeKind, loop: Bool) {
        if case .silence = kind {
            stop()
            return
        }
        guard let url = PresetSoundscapes.url(for: kind) else {
            stop()
            return
        }
        playFile(at: url, loop: loop)
    }

    /// 任意の音声ファイル(録音m4a等)を再生する。
    func playFile(at url: URL, loop: Bool) {
        stop()
        activateSession()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = loop ? -1 : 0
            newPlayer.volume = 1.0
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                isPlaying = false
                return
            }
            player = newPlayer
            isPlaying = true
            if !loop {
                scheduleFinishWatcher(after: max(0.1, newPlayer.duration) + 0.3)
            }
        } catch {
            player = nil
            isPlaying = false
        }
    }

    /// 再生を停止する(フェードなしの即時停止)。
    func stop() {
        finishWatcher?.cancel()
        finishWatcher = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: - 内部

    /// ループなし再生の終了を検知して isPlaying を戻す
    private func scheduleFinishWatcher(after seconds: TimeInterval) {
        finishWatcher?.cancel()
        finishWatcher = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            if self.player?.isPlaying != true {
                self.player = nil
                self.isPlaying = false
            }
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])
    }
}
