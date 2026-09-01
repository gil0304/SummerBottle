//
//  PresetSoundscapes.swift
//  SummerBottle
//
//  プリセット環境音のプロシージャル生成。
//  16bit / 44.1kHz / モノラル / 15秒 の PCM を数式で合成し、
//  WAV(44byte RIFFヘッダ)をキャッシュディレクトリへ書き出す。
//  生成は初回のみ(以後はキャッシュファイルを返す)。乱数はシード付きの
//  線形合同法なので、毎回まったく同じ音になる。
//

import Foundation

// MARK: - シード付き乱数(線形合同法)

/// 毎回同じ音を合成するための決定論的乱数。
nonisolated fileprivate struct SoundscapeRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 2862933555777941757 &+ 3037000493
    }

    /// [0, 1) の一様乱数
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) * (1.0 / 9007199254740992.0)
    }

    /// [-1, 1) の一様乱数
    mutating func bipolar() -> Double {
        next() * 2.0 - 1.0
    }

    /// [lo, hi) の一様乱数
    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }
}

// MARK: - プリセット環境音

enum PresetSoundscapes {

    // 合成パラメータ
    nonisolated private static let sampleRate: Double = 44100
    nonisolated private static let clipDuration: Double = 15
    nonisolated private static let sampleCount: Int = Int(sampleRate * clipDuration)

    /// 同時生成防止用ロック(url(for:) は任意スレッドから呼ばれ得る)
    nonisolated private static let generationLock = NSLock()

    /// 指定した環境音のWAVファイルURLを返す。silence は nil。
    /// 初回呼び出し時に合成してキャッシュへ書き出し、以後はキャッシュを返す。
    nonisolated static func url(for kind: SoundscapeKind) -> URL? {
        if case .silence = kind { return nil }

        generationLock.lock()
        defer { generationLock.unlock() }

        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Soundscapes", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("soundscape-\(kind.rawValue)-v1.wav")
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let raw = rawSamples(for: kind)
        let pcm = finalized(raw)
        let data = wavData(from: pcm)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - レシピ振り分け

    nonisolated private static func rawSamples(for kind: SoundscapeKind) -> [Double] {
        switch kind {
        case .waves: return makeWaves()
        case .cicadas: return makeCicadas()
        case .fireworks: return makeFireworks()
        case .festival: return makeFestival()
        case .wind: return makeWind()
        case .nightInsects: return makeNightInsects()
        case .silence: return [Double](repeating: 0, count: sampleCount)
        }
    }

    // MARK: - 波音
    // ホワイトノイズ ×(0.3 + 0.7·sin(2πt/7)²)の包絡 → 単純移動平均のローパス。

    nonisolated private static func makeWaves() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0x57A7E5)
        var modulated = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let swell = sin(2.0 * .pi * t / 7.0)
            let envelope = 0.3 + 0.7 * swell * swell
            modulated[i] = rng.bipolar() * envelope
        }
        // 移動平均を2段かけて「ざあぁ…」という柔らかい帯域にする
        return movingAverage(movingAverage(modulated, window: 20), window: 10)
    }

    // MARK: - セミ
    // 4〜6kHz 矩形波の断続バースト(ジージー)+ かすかな背景ノイズ。

    nonisolated private static func makeCicadas() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0xC1CADA)
        var out = [Double](repeating: 0, count: n)

        // 背景のかすかな空気感
        for i in 0..<n {
            out[i] = hashNoise(i) * 0.01
        }

        func addBurst(start: Double, length: Double, baseFreq: Double, amp: Double) {
            let startIndex = Int(start * sampleRate)
            let count = Int(length * sampleRate)
            var phase = 0.0
            for j in 0..<count {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                // 周波数を5Hzで揺らして「ジー」の質感を出す
                let freq = baseFreq + 250.0 * sin(2.0 * .pi * 5.0 * t)
                phase += freq / sampleRate
                let square: Double = phase.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1.0 : -1.0
                // 27Hzの振幅変調で「ジジジ…」
                let buzz = 0.55 + 0.45 * sin(2.0 * .pi * 27.0 * t)
                let attack = min(1.0, t / 0.08)
                let release = min(1.0, max(0.0, (length - t) / 0.15))
                out[index] += square * buzz * attack * release * amp
            }
        }

        // 2匹のセミが交互に鳴く
        for voice in 0..<2 {
            let baseFreq = 4300.0 + Double(voice) * 1100.0 + rng.range(-150, 150)
            var t = rng.range(0.1, 0.8)
            while t < clipDuration - 0.5 {
                let length = rng.range(0.9, 2.2)
                addBurst(start: t,
                         length: min(length, clipDuration - t - 0.1),
                         baseFreq: baseFreq,
                         amp: voice == 0 ? 0.30 : 0.18)
                t += length + rng.range(0.25, 1.0)
            }
        }
        return out
    }

    // MARK: - 花火
    // ランダム時刻に減衰ノイズの破裂(exp減衰)+ 低域の「ドン」。

    nonisolated private static func makeFireworks() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0xF12E)
        var out = [Double](repeating: 0, count: n)

        func addBurst(at start: Double, strength: Double) {
            let startIndex = Int(start * sampleRate)
            // 低域の「ドン」: 50〜70Hzからピッチが沈む正弦波
            let boomFreq = rng.range(48, 68)
            let boomCount = Int(1.0 * sampleRate)
            for j in 0..<boomCount {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                let freq = boomFreq * (1.0 - 0.35 * min(1.0, t / 0.5))
                out[index] += sin(2.0 * .pi * freq * t) * exp(-t / 0.28) * strength
            }
            // 破裂と残響: exp減衰するノイズ
            let crackCount = Int(1.8 * sampleRate)
            for j in 0..<crackCount {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                out[index] += rng.bipolar() * exp(-t / 0.5) * 0.55 * strength
            }
        }

        var t = 0.4
        var count = 0
        while t < clipDuration - 1.2 && count < 8 {
            addBurst(at: t, strength: rng.range(0.7, 1.0))
            t += rng.range(1.0, 2.6)
            count += 1
        }
        return out
    }

    // MARK: - 祭り囃子
    // 110Hz付近の太鼓パルス(4つ打ち+裏)+ 笛風の正弦メロディ(ペンタトニック)。

    nonisolated private static func makeFestival() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0xFE57)
        var out = [Double](repeating: 0, count: n)
        let beat = 0.5 // 120BPM → 15秒でちょうど30拍(ループが揃う)
        let beats = Int(clipDuration / beat)

        func addDrum(at start: Double, amp: Double) {
            let startIndex = Int(start * sampleRate)
            let count = Int(0.3 * sampleRate)
            for j in 0..<count {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                // 110Hzから沈み込むピッチで「ドン」
                let freq = 110.0 * (1.0 - 0.35 * min(1.0, t / 0.18))
                let body = sin(2.0 * .pi * freq * t) * exp(-t / 0.075)
                let attack = hashNoise(index) * exp(-t / 0.012) * 0.4
                out[index] += (body + attack) * amp
            }
        }

        // 4つ打ち+裏(偶数拍の裏に小さい打ち込み)
        for k in 0..<beats {
            let t0 = Double(k) * beat
            addDrum(at: t0, amp: k % 4 == 0 ? 0.9 : 0.6)
            if k % 2 == 1 {
                addDrum(at: t0 + beat / 2.0, amp: 0.3)
            }
        }

        // 笛: ペンタトニック上をランダムウォークする正弦メロディ(ビブラート付き)
        let pentatonic: [Double] = [880.00, 987.77, 1174.66, 1318.51, 1479.98]

        func addFlute(start: Double, length: Double, freq: Double) {
            let startIndex = Int(start * sampleRate)
            let count = Int(length * sampleRate)
            var phase = 0.0
            for j in 0..<count {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                let vibrato = 1.0 + 0.006 * sin(2.0 * .pi * 5.5 * t)
                phase += freq * vibrato / sampleRate
                let attack = min(1.0, t / 0.04)
                let release = min(1.0, max(0.0, (length - t) / 0.09))
                let tone = sin(2.0 * .pi * phase) + 0.35 * sin(4.0 * .pi * phase)
                out[index] += tone * attack * release * 0.18
            }
        }

        var noteTime = 0.0
        var degree = 2
        while noteTime < clipDuration - 0.05 {
            let hold = rng.next() < 0.3 ? 1.0 : 0.5
            let step = Int(rng.range(0, 3)) - 1 // -1, 0, +1
            degree = max(0, min(pentatonic.count - 1, degree + step))
            addFlute(start: noteTime,
                     length: min(hold, clipDuration - noteTime) - 0.03,
                     freq: pentatonic[degree])
            noteTime += hold
        }
        return out
    }

    // MARK: - 風
    // 帯域ノイズ(移動平均の差分)を長周期LFOで振幅変調。

    nonisolated private static func makeWind() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0x0111D)
        var noise = [Double](repeating: 0, count: n)
        for i in 0..<n {
            noise[i] = rng.bipolar()
        }
        // 短い移動平均 − 長い移動平均 ≒ バンドパス
        let short = movingAverage(noise, window: 6)
        let long = movingAverage(noise, window: 40)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            // 9秒周期のうねり × 2.3秒周期の細かい揺らぎ
            let gustBase = 0.5 + 0.5 * sin(2.0 * .pi * t / 9.0 + 0.8)
            let gust = 0.35 + 0.65 * gustBase * gustBase
            let flutter = 0.8 + 0.2 * sin(2.0 * .pi * t / 2.3)
            out[i] = (short[i] - long[i]) * gust * flutter
        }
        return out
    }

    // MARK: - 夜の虫
    // コオロギ風: 3kHz正弦の短いチャープ3連 × 繰り返し + 間。

    nonisolated private static func makeNightInsects() -> [Double] {
        let n = sampleCount
        var rng = SoundscapeRandom(seed: 0x1758C7)
        var out = [Double](repeating: 0, count: n)
        let chirpLength = 0.06

        func addChirp(at start: Double, freq: Double, amp: Double) {
            let startIndex = Int(start * sampleRate)
            let count = Int(chirpLength * sampleRate)
            for j in 0..<count {
                let index = startIndex + j
                if index >= n { break }
                let t = Double(j) / sampleRate
                let envelope = sin(.pi * t / chirpLength) // なめらかな半正弦包絡
                let ripple = 0.6 + 0.4 * sin(2.0 * .pi * 220.0 * t) // 内部の細かい脈動
                out[index] += sin(2.0 * .pi * freq * t) * envelope * ripple * amp
            }
        }

        // コオロギ1(3kHz)
        var t = 0.3
        while t < clipDuration - 0.5 {
            for c in 0..<3 {
                addChirp(at: t + Double(c) * 0.1, freq: 3000, amp: 0.5)
            }
            t += rng.range(0.7, 1.3)
        }
        // コオロギ2(3.45kHz、少し遠く)
        var t2 = 0.55
        while t2 < clipDuration - 0.5 {
            for c in 0..<3 {
                addChirp(at: t2 + Double(c) * 0.09, freq: 3450, amp: 0.28)
            }
            t2 += rng.range(0.9, 1.6)
        }
        // 夜の空気(ごく薄いノイズ)
        for i in 0..<n {
            out[i] += hashNoise(i) * 0.004
        }
        return out
    }

    // MARK: - 共通ヘルパー

    /// 単純移動平均(ローパス)。先頭は伸びている分だけの平均で正規化。
    nonisolated private static func movingAverage(_ input: [Double], window: Int) -> [Double] {
        guard window > 1 else { return input }
        var out = [Double](repeating: 0, count: input.count)
        var sum = 0.0
        for i in 0..<input.count {
            sum += input[i]
            if i >= window {
                sum -= input[i - window]
            }
            out[i] = sum / Double(min(i + 1, window))
        }
        return out
    }

    /// 乱数状態を消費しない決定論的ノイズ(サンプル位置のハッシュ)
    nonisolated private static func hashNoise(_ index: Int) -> Double {
        let x = sin(Double(index) * 12.9898 + 78.233) * 43758.5453
        return (x - x.rounded(.down)) * 2.0 - 1.0
    }

    /// ピーク正規化(0.85)+ クリック防止の先頭末尾フェード + Int16量子化
    nonisolated private static func finalized(_ input: [Double]) -> [Int16] {
        var samples = input
        let n = samples.count
        var peak = 0.0
        for value in samples {
            peak = max(peak, abs(value))
        }
        let gain = peak > 0.0001 ? 0.85 / peak : 0.0
        let fadeCount = max(1, Int(0.15 * sampleRate))
        for i in 0..<n {
            var value = samples[i] * gain
            if i < fadeCount {
                value *= Double(i) / Double(fadeCount)
            }
            let tail = n - 1 - i
            if tail < fadeCount {
                value *= Double(tail) / Double(fadeCount)
            }
            samples[i] = value
        }
        return samples.map { Int16(max(-32767.0, min(32767.0, $0 * 32767.0))) }
    }

    /// 44byteのRIFF/WAVEヘッダを自前で書いた 16bit PCM モノラル WAV データ
    nonisolated private static func wavData(from samples: [Int16]) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + dataSize)

        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append32(_ value: UInt32) {
            let v = value.littleEndian
            withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            let v = value.littleEndian
            withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)                          // fmtチャンクサイズ
        append16(1)                           // PCM
        append16(1)                           // モノラル
        append32(UInt32(sampleRate))          // サンプルレート
        append32(UInt32(sampleRate) * 2)      // バイトレート(mono 16bit)
        append16(2)                           // ブロックアライン
        append16(16)                          // ビット深度
        append("data")
        append32(UInt32(dataSize))

        let payload = samples.map { $0.littleEndian }
        payload.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
