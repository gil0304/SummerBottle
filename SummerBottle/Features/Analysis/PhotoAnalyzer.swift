//
//  PhotoAnalyzer.swift
//  SummerBottle
//
//  Vision による写真解析(契約書3章)。
//  - VNClassifyImageRequest の分類ラベルを PhotoElement へマッピング(confidence >= 0.3)
//  - 縮小画像のピクセル走査による主色抽出(RGB各4bit量子化ヒストグラムの上位5色)
//  - EXIF撮影日時 → TimeOfDay.estimate、EXIFなしは平均輝度・色温度から昼/夕/夜を推定
//  - 夏らしい物体ラベルを summerObjects へ(生identifierのまま)
//  すべてバックグラウンドで実行し、メインスレッドをブロックしない。
//  顔認識・個人特定は行わない。
//

import Foundation
import CoreGraphics
import Vision

enum PhotoAnalyzer {

    /// Visionで写真を解析する。メインスレッドをブロックしないこと(nonisolated)。
    nonisolated static func analyze(imageData: Data) async -> PhotoAnalysis {
        var analysis = await withCheckedContinuation { (continuation: CheckedContinuation<PhotoAnalysis, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: performAnalysis(imageData: imageData))
            }
        }
        // EXIF撮影日時があれば共有ロジック(TimeOfDay.estimate)で時間帯を確定する。
        // (なければ performAnalysis 内の画調推定の結果がそのまま残る)
        if let captured = analysis.capturedAt {
            analysis.timeOfDay = await TimeOfDay.estimate(from: captured)
        }
        return analysis
    }

    // MARK: - 解析本体(バックグラウンドスレッドで実行)

    private nonisolated static func performAnalysis(imageData: Data) -> PhotoAnalysis {
        var analysis = PhotoAnalysis()
        analysis.capturedAt = ImageUtil.captureDate(from: imageData)

        classify(imageData: imageData, into: &analysis)

        if let thumbnail = ImageUtil.cgImage(from: imageData, maxPixel: 64) {
            let stats = colorStats(of: thumbnail)
            analysis.dominantColorHexes = stats.topHexes
            // EXIFがない場合の画調ベース推定(EXIFがあれば analyze 側で上書きされる)
            analysis.timeOfDay = estimateTimeOfDay(from: stats)
        }
        return analysis
    }

    // MARK: - Vision 分類

    private nonisolated static func classify(imageData: Data, into analysis: inout PhotoAnalysis) {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let observations = request.results else { return }

        for observation in observations where observation.confidence >= 0.3 {
            let identifier = observation.identifier.lowercased()
            let tokens = tokenize(identifier)
            for token in tokens {
                if let mapped = elementKeywords[token] {
                    for element in mapped {
                        analysis.elements.insert(element)
                    }
                }
            }
            if tokens.contains(where: { summerKeywords.contains($0) }),
               !analysis.summerObjects.contains(identifier) {
                analysis.summerObjects.append(identifier)
            }
        }
    }

    /// identifier を英字トークンに分解する("ice_cream" → ["ice", "cream"])
    private nonisolated static func tokenize(_ identifier: String) -> [String] {
        identifier.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// 分類ラベルのトークン → PhotoElement 対応表
    private nonisolated static let elementKeywords: [String: [PhotoElement]] = [
        // 海辺
        "beach": [.beach, .sea],
        "coast": [.beach, .sea],
        "seashore": [.beach, .sea],
        "shore": [.beach, .sea],
        "ocean": [.sea],
        "sea": [.sea],
        // 空
        "sky": [.sky],
        "cloud": [.sky],
        // 山
        "mountain": [.mountain],
        "hill": [.mountain],
        // 街
        "city": [.city],
        "cityscape": [.city],
        "building": [.city],
        "street": [.city],
        "skyscraper": [.city],
        "downtown": [.city],
        // 花火
        "firework": [.fireworks],
        "fireworks": [.fireworks],
        // 食べ物
        "food": [.food],
        "dish": [.food],
        "meal": [.food],
        "dessert": [.food],
        "cuisine": [.food],
        "snack": [.food],
        // 人・動物
        "people": [.person],
        "person": [.person],
        "dog": [.animal],
        "cat": [.animal],
        "bird": [.animal],
        "animal": [.animal],
        "pet": [.animal],
        // 屋内外
        "indoor": [.indoor],
        "outdoor": [.outdoor],
        // プール・公園
        "pool": [.pool],
        "poolside": [.pool],
        "park": [.park],
        "garden": [.park],
        // 夕焼け・夜
        "sunset": [.sunset],
        "dusk": [.sunset],
        "night": [.night],
        "nighttime": [.night],
        // 祭り
        "festival": [.festival],
        "carnival": [.festival],
        "lantern": [.festival],
    ]

    /// 夏らしい物体を示すトークン(該当した分類ラベルは生identifierのまま summerObjects へ)
    private nonisolated static let summerKeywords: Set<String> = [
        "watermelon", "melon",
        "ice", "icecream", "popsicle", "sundae", "shaved",
        "beach", "sea", "wave", "surf", "surfing", "swimming",
        "firework", "fireworks",
        "pool",
        "sunflower", "cicada",
        "lantern", "festival",
        "parasol", "seashell", "shell",
    ]

    // MARK: - 主色・画調

    private typealias PhotoColorStats = (topHexes: [String], luminance: Double, red: Double, blue: Double)

    /// 縮小画像をRGBA8で走査し、4bit量子化ヒストグラムの上位5色と平均輝度・色味を求める
    private nonisolated static func colorStats(of image: CGImage) -> PhotoColorStats {
        let width = image.width
        let height = image.height
        let fallback: PhotoColorStats = ([], 0.5, 0.5, 0.5)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return fallback }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { return fallback }

        let pixelCount = width * height
        let pixels = base.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        // RGB各4bit(計12bit=4096バケット)に量子化して頻度を数える
        var histogram = [Int](repeating: 0, count: 4096)
        var sumR = 0
        var sumG = 0
        var sumB = 0
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            histogram[((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)] += 1
            sumR += r
            sumG += g
            sumB += b
        }

        let denom = Double(pixelCount) * 255
        let avgR = Double(sumR) / denom
        let avgG = Double(sumG) / denom
        let avgB = Double(sumB) / denom
        let luminance = 0.299 * avgR + 0.587 * avgG + 0.114 * avgB

        let topBuckets = histogram.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(5)
        let hexes = topBuckets.map { entry -> String in
            // バケット中心の色に戻す
            let r = (((entry.offset >> 8) & 0xF) << 4) | 0x8
            let g = (((entry.offset >> 4) & 0xF) << 4) | 0x8
            let b = ((entry.offset & 0xF) << 4) | 0x8
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return (Array(hexes), luminance, avgR, avgB)
    }

    /// EXIFがないときの推定: 平均輝度と色温度(赤み−青み)から昼/夕/夜を判定する
    private nonisolated static func estimateTimeOfDay(from stats: PhotoColorStats) -> TimeOfDay {
        let warmth = stats.red - stats.blue
        if stats.luminance < 0.22 {
            return .night
        }
        if warmth > 0.10 && stats.luminance < 0.62 {
            return .evening
        }
        if warmth > 0.04 && stats.luminance < 0.32 {
            return .evening
        }
        return .daytime
    }
}
