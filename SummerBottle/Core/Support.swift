//
//  Support.swift
//  SummerBottle
//
//  共有ユーティリティ: テーマ、色hex変換、画像縮小、ハプティクス、日付整形。
//  ※ グローバルなextensionはこのファイルにのみ定義する(重複宣言防止)。
//

import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - テーマ

enum AppTheme {
    // 夏のパレット
    static let ocean = Color(hex: "#2E8BC0")
    static let deepSea = Color(hex: "#145DA0")
    static let sand = Color(hex: "#F5E6C8")
    static let coral = Color(hex: "#FF7F66")
    static let sunset = Color(hex: "#FF9E5E")
    static let nightNavy = Color(hex: "#1A2238")
    static let shelfWood = Color(hex: "#B08968")
    static let glassTint = Color(hex: "#D8F0F2")

    /// 時間帯に応じた空のグラデーション(背景UI用)
    static func skyGradient(for timeOfDay: TimeOfDay) -> LinearGradient {
        let colors: [Color] = switch timeOfDay {
        case .morning: [Color(hex: "#BEE3F0"), Color(hex: "#FDF3DE")]
        case .daytime: [Color(hex: "#5EB0E5"), Color(hex: "#BDE3F5")]
        case .evening: [Color(hex: "#FF9E5E"), Color(hex: "#FFD9A0")]
        case .night: [Color(hex: "#141A33"), Color(hex: "#2A3560")]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// 時間帯のデフォルト空色(SceneConfig初期値用)
    static func defaultSkyHex(for timeOfDay: TimeOfDay) -> String {
        switch timeOfDay {
        case .morning: "#A8D5E8"
        case .daytime: "#5EB0E5"
        case .evening: "#FF9E5E"
        case .night: "#141A33"
        }
    }

    /// 時間帯のデフォルト海色
    static func defaultSeaHex(for timeOfDay: TimeOfDay) -> String {
        switch timeOfDay {
        case .morning: "#7FBFD4"
        case .daytime: "#2E8BC0"
        case .evening: "#C77B4F"
        case .night: "#16324A"
        }
    }
}

// MARK: - 色 hex 変換

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        var hexString = hex.trimmingCharacters(in: .whitespaces)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        let r, g, b: CGFloat
        if hexString.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { min(255, max(0, Int(v * 255))) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    var hexString: String {
        UIColor(self).hexString
    }
}

// MARK: - 画像ユーティリティ

enum ImageUtil {
    /// JPEG/HEICデータを最大辺 maxPixel に縮小したJPEGへ変換する(アップロード・保存前の縮小)
    nonisolated static func downscaledJPEGData(from data: Data, maxPixel: CGFloat = 2048, quality: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }

    /// データからCGImageを取得(最大辺 maxPixel に縮小)
    nonisolated static func cgImage(from data: Data, maxPixel: CGFloat = 1024) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// ファイルからCGImageを取得(最大辺 maxPixel に縮小)
    nonisolated static func cgImage(contentsOf url: URL, maxPixel: CGFloat = 1024) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// EXIFから撮影日時を取り出す
    nonisolated static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}

// MARK: - ハプティクス

@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - 日付整形

extension Date {
    /// 例: 2026年7月13日
    var japaneseDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: self)
    }

    /// 例: 7/13
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter.string(from: self)
    }

    /// 例: 2026年7月
    var yearMonthString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: self)
    }
}
