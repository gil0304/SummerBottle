//
//  SceneComposer.swift
//  SummerBottle
//
//  シーン自動構成(契約書4章 / 仕様書7章のルール表)。
//  写真解析結果と下書き情報から SceneConfig を自動生成する。
//  - 時間帯: 手動指定 → 写真の多数決 → 思い出の日付の時刻
//  - 検出内容/思い出の種類 → ミニチュア(3〜8個)を黄金角で円周上に配置
//  - フォトカード最大3枚を目立つ高さ(y 0.35〜0.55)に配置
//  - ボトル形状推奨・パーティクル・環境音・ラベル文の生成
//

import Foundation
import UIKit
import SwiftUI

@MainActor
enum SceneComposer {

    /// 下書き(写真解析済み)から SceneConfig を自動生成する(仕様書7章のルール)
    static func compose(draft: BottleDraft) -> SceneConfig {
        let analyses = draft.photos.compactMap { $0.analysis }

        // 検出要素の集約 + MemoryType による補完
        var traits: Set<PhotoElement> = []
        for analysis in analyses {
            traits.formUnion(analysis.elements)
        }
        traits.formUnion(supplementalElements(for: draft.memoryType))

        let summerObjects = analyses.flatMap { $0.summerObjects }

        // 時間帯: 手動 → 写真の多数決 → 思い出の日付の時刻
        var timeOfDay: TimeOfDay
        if let manual = draft.timeOverride {
            timeOfDay = manual
        } else if let voted = majorityTimeOfDay(analyses.compactMap { $0.timeOfDay }) {
            timeOfDay = voted
        } else {
            timeOfDay = TimeOfDay.estimate(from: draft.memoryDate)
        }
        // 花火は夜空に(手動指定がなければ)
        if draft.timeOverride == nil,
           traits.contains(.fireworks) || draft.memoryType == .fireworks {
            timeOfDay = .night
        }

        // 天気: 手動 → 既定は晴れ
        let weather = draft.weatherOverride ?? .sunny

        let hasSea = traits.contains(.sea) || traits.contains(.beach)

        // 空色・海色: 時間帯プリセットを基準に、写真の主色へ少し寄せる
        var skyHex = AppTheme.defaultSkyHex(for: timeOfDay)
        var seaHex = AppTheme.defaultSeaHex(for: timeOfDay)
        let dominantHexes = analyses.flatMap { $0.dominantColorHexes }
        if let bluish = dominantHexes.first(where: isBluish) {
            seaHex = blendHex(base: seaHex, toward: bluish, amount: 0.35)
            if timeOfDay == .daytime || timeOfDay == .morning {
                skyHex = blendHex(base: skyHex, toward: bluish, amount: 0.2)
            }
        }
        if timeOfDay == .evening, let warm = dominantHexes.first(where: isOrangish) {
            skyHex = blendHex(base: skyHex, toward: warm, amount: 0.3)
        }

        // ミニチュアの種類を決める(3〜8個)
        let miniatureTypes = decideMiniatureTypes(
            draft: draft,
            traits: traits,
            summerObjects: summerObjects,
            hasSea: hasSea,
            timeOfDay: timeOfDay,
            weather: weather
        )

        // 配置: 黄金角(約137.5度)で円周上に散らし、向きは中心向き。重なりは回避する
        var objects = placeMiniatures(miniatureTypes)

        // フォトカード: 最大3枚を目立つ高さに(y 0.35〜0.55)
        objects.append(contentsOf: makePhotoCards(draft: draft))

        // ボトル形状の推奨
        let seaPhotoCount = analyses.filter {
            $0.elements.contains(.sea) || $0.elements.contains(.beach)
        }.count
        let seaIsWide = analyses.count >= 2 && seaPhotoCount * 2 >= analyses.count
        let bottleType = recommendBottleType(
            draft: draft,
            traits: traits,
            timeOfDay: timeOfDay,
            seaIsWide: seaIsWide
        )

        // パーティクル
        let particle: ParticleKind
        if traits.contains(.fireworks) || traits.contains(.festival) {
            particle = .sparks
        } else if timeOfDay == .night {
            particle = (traits.contains(.park) || draft.memoryType == .camp) ? .fireflies : .stars
        } else if hasSea {
            particle = .splash
        } else if traits.contains(.pool) {
            particle = .bubbles
        } else if traits.contains(.park) {
            particle = .petals
        } else {
            particle = .none
        }

        // 環境音
        let soundscape: SoundscapeKind
        if traits.contains(.fireworks) {
            soundscape = .fireworks
        } else if traits.contains(.festival) {
            soundscape = .festival
        } else if hasSea {
            soundscape = .waves
        } else if timeOfDay == .night {
            soundscape = .nightInsects
        } else if timeOfDay == .daytime || timeOfDay == .morning {
            soundscape = .cicadas
        } else {
            soundscape = .wind
        }

        // 砂の量
        let sandAmount: Double
        if hasSea {
            sandAmount = 0.6
        } else if traits.contains(.park) || traits.contains(.mountain) || draft.memoryType == .camp {
            sandAmount = 0.3
        } else if traits.contains(.city) || traits.contains(.indoor) {
            sandAmount = 0.15
        } else {
            sandAmount = 0.35
        }

        var config = SceneConfig()
        config.bottleType = bottleType
        config.timeOfDay = timeOfDay
        config.weather = weather
        config.skyColorHex = skyHex
        config.seaColorHex = seaHex
        config.hasSea = hasSea
        config.sandAmount = sandAmount
        config.labelText = makeLabelText(
            draft: draft,
            traits: traits,
            summerObjects: summerObjects,
            timeOfDay: timeOfDay
        )
        config.particle = particle
        config.soundscape = soundscape
        config.objects = objects
        return config
    }

    // MARK: - 時間帯の多数決

    private static func majorityTimeOfDay(_ votes: [TimeOfDay]) -> TimeOfDay? {
        guard !votes.isEmpty else { return nil }
        var counts: [TimeOfDay: Int] = [:]
        for vote in votes {
            counts[vote, default: 0] += 1
        }
        var best: TimeOfDay?
        var bestCount = 0
        // allCases の順で走査し、同数の場合は先の時間帯を採用(決定的)
        for candidate in TimeOfDay.allCases {
            if let count = counts[candidate], count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return best
    }

    // MARK: - MemoryType による要素補完

    private static func supplementalElements(for memoryType: MemoryType?) -> Set<PhotoElement> {
        switch memoryType {
        case .sea:
            return [.sea, .beach]
        case .festival:
            return [.festival]
        case .fireworks:
            return [.fireworks]
        case .park:
            return [.park]
        case .cityWalk:
            return [.city]
        case .meal:
            return [.food]
        case .camp:
            return [.mountain, .outdoor]
        case .drive:
            // 小舟は使わず街/山要素で補完
            return [.city, .mountain]
        case .trip, .ordinary, .other, .none:
            return []
        }
    }

    // MARK: - ミニチュア種類の決定

    private static func decideMiniatureTypes(
        draft: BottleDraft,
        traits: Set<PhotoElement>,
        summerObjects: [String],
        hasSea: Bool,
        timeOfDay: TimeOfDay,
        weather: WeatherKind
    ) -> [SceneObjectType] {
        var types: [SceneObjectType] = []
        func add(_ type: SceneObjectType) {
            if !types.contains(type) {
                types.append(type)
            }
        }

        // 特徴的な要素から順に(仕様書7.3の対応表)
        if traits.contains(.fireworks) { add(.fireworks) }
        if traits.contains(.festival) {
            add(.lanternString)
            add(.stall)
            add(.torii)
        }
        if hasSea {
            add(.parasol)
            add(.floatRing)
            add(.shell)
        }
        if traits.contains(.pool) {
            add(.pool)
            add(.floatRing)
        }
        if draft.memoryType == .camp {
            add(.tent)
            add(.campfire)
        }
        if traits.contains(.food) {
            add(.table)
            add(.food)
        }
        if traits.contains(.mountain) {
            add(.mountain)
            add(.tree)
        }
        if traits.contains(.city) {
            add(.building)
            add(.streetLight)
        }
        if traits.contains(.park) {
            add(.grass)
            add(.bench)
            add(.tree)
        }
        if draft.memoryType == .trip, hasSea {
            add(.boat)
        }

        // 夏らしい検出物
        if summerObjects.contains(where: { $0.contains("watermelon") || $0.contains("melon") }) {
            add(.watermelon)
        }
        if summerObjects.contains(where: { $0.contains("ice") || $0.contains("shaved") }) {
            add(.shavedIce)
        }

        // 彩り: 海辺のヤシの木、昼間の入道雲
        if hasSea, types.count < 7 {
            add(.palmTree)
        }
        if timeOfDay != .night, weather != .rain, types.count < 8 {
            add(.cloud)
        }

        // 最低3個は置く
        if types.count < 3 {
            let filler: [SceneObjectType] = timeOfDay == .night
                ? [.streetLight, .lanternString, .grass, .watermelon]
                : [.cloud, .watermelon, .tree, .shavedIce]
            for type in filler where types.count < 3 {
                add(type)
            }
        }

        // 最大8個
        return Array(types.prefix(8))
    }

    // MARK: - 配置

    private static func placeMiniatures(_ types: [SceneObjectType]) -> [SceneObject] {
        let goldenAngle: Float = 2.3999632  // 約137.5度
        let radii: [Float] = [0.55, 0.70, 0.42, 0.63, 0.50, 0.74, 0.38, 0.67]

        var objects: [SceneObject] = []
        var placed: [SIMD2<Float>] = []

        func isTooClose(_ x: Float, _ z: Float) -> Bool {
            placed.contains { other in
                let dx = other.x - x
                let dz = other.y - z
                return dx * dx + dz * dz < 0.078  // 距離 約0.28 未満
            }
        }

        for (index, type) in types.enumerated() {
            var angle = Float(index) * goldenAngle + 0.7
            var radius = radii[index % radii.count]
            var x = radius * cosf(angle)
            var z = radius * sinf(angle)

            // 重なり回避: 近すぎたら少し回しながら外側へずらす
            var attempts = 0
            while isTooClose(x, z), attempts < 8 {
                angle += 0.5
                radius = min(0.75, radius + 0.05)
                x = radius * cosf(angle)
                z = radius * sinf(angle)
                attempts += 1
            }
            placed.append(SIMD2<Float>(x, z))

            objects.append(SceneObject(
                type: type,
                position: SIMD3<Float>(x, floorHeight(for: type, index: index), z),
                rotationY: atan2f(x, z),  // 中心向き
                scale: 0.85 + Float((index * 37) % 30) / 100  // 0.85〜1.14 の決定的ゆらぎ
            ))
        }
        return objects
    }

    private static func floorHeight(for type: SceneObjectType, index: Int) -> Float {
        switch type {
        case .cloud:
            return 0.68 + Float(index % 3) * 0.05
        case .fireworks:
            return 0.78
        case .lanternString:
            return 0.5
        default:
            return 0
        }
    }

    private static func makePhotoCards(draft: BottleDraft) -> [SceneObject] {
        let cardCount = min(3, draft.photos.count)
        guard cardCount > 0 else { return [] }
        // 1枚目は正面ど真ん中に大きく(瓶の主役)、2枚目以降は左右後方に小さめ。
        // 回転すると次の写真が現れる配置にする。
        let placements: [(x: Float, y: Float, z: Float, scale: Float)] = [
            (0.00, 0.40, 0.58, 1.15),
            (-0.60, 0.52, -0.32, 0.85),
            (0.60, 0.33, -0.36, 0.85),
        ]
        var cards: [SceneObject] = []
        for i in 0..<cardCount {
            let placement = placements[i]
            cards.append(SceneObject(
                type: .photoCard,
                position: SIMD3<Float>(placement.x, placement.y, placement.z),
                rotationY: atan2f(placement.x, placement.z),
                scale: placement.scale,
                photoID: draft.photos[i].id
            ))
        }
        return cards
    }

    // MARK: - ボトル形状の推奨

    private static func recommendBottleType(
        draft: BottleDraft,
        traits: Set<PhotoElement>,
        timeOfDay: TimeOfDay,
        seaIsWide: Bool
    ) -> BottleType {
        if timeOfDay == .night
            || traits.contains(.fireworks) || traits.contains(.festival)
            || draft.memoryType == .fireworks || draft.memoryType == .festival {
            return .lantern
        }
        if draft.memoryType == .sea || draft.memoryType == .trip {
            return .drift
        }
        if draft.photos.count == 1 {
            return .mini
        }
        if seaIsWide {
            return .round
        }
        return .standard
    }

    // MARK: - ラベル文

    private static func makeLabelText(
        draft: BottleDraft,
        traits: Set<PhotoElement>,
        summerObjects: [String],
        timeOfDay: TimeOfDay
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.M.d"
        var head = formatter.string(from: draft.memoryDate)

        let location = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty {
            head += " " + location
        }

        let phrase = makePhrase(
            draft: draft,
            traits: traits,
            summerObjects: summerObjects,
            timeOfDay: timeOfDay
        )
        return phrase.isEmpty ? head : head + " — " + phrase
    }

    private static func makePhrase(
        draft: BottleDraft,
        traits: Set<PhotoElement>,
        summerObjects: [String],
        timeOfDay: TimeOfDay
    ) -> String {
        // 一言があれば最優先(1行目を短く整える)
        let comment = (draft.comment.components(separatedBy: .newlines).first ?? "")
            .trimmingCharacters(in: .whitespaces)
        if !comment.isEmpty {
            return comment.count <= 20 ? comment : String(comment.prefix(18)) + "…"
        }

        let timeWord: String
        switch timeOfDay {
        case .morning: timeWord = "朝"
        case .daytime: timeWord = "午後"
        case .evening: timeWord = "夕暮れ"
        case .night: timeWord = "夜"
        }

        let motif = primaryMotif(traits: traits, memoryType: draft.memoryType)
        let objectWord = summerObjectWord(summerObjects: summerObjects)

        if let motif, let objectWord {
            return "\(motif)と、\(objectWord)の\(timeWord)"
        }
        if let motif {
            return "\(motif)を閉じ込めた\(timeWord)"
        }
        if let objectWord {
            return "\(objectWord)の\(timeWord)"
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.count <= 14 {
            return title
        }
        return "夏のひとかけら"
    }

    private static func primaryMotif(traits: Set<PhotoElement>, memoryType: MemoryType?) -> String? {
        if traits.contains(.fireworks) { return "夜空の花火" }
        if traits.contains(.festival) { return "祭りのざわめき" }
        if traits.contains(.sea) || traits.contains(.beach) { return "波の音" }
        if traits.contains(.pool) { return "水しぶき" }
        if memoryType == .camp { return "焚き火の匂い" }
        if traits.contains(.mountain) { return "山の風" }
        if traits.contains(.park) { return "木漏れ日" }
        if traits.contains(.city) { return "街のざわめき" }
        if traits.contains(.food) { return "おいしい匂い" }
        return nil
    }

    private static func summerObjectWord(summerObjects: [String]) -> String? {
        if summerObjects.contains(where: { $0.contains("watermelon") || $0.contains("melon") }) {
            return "スイカ"
        }
        if summerObjects.contains(where: { $0.contains("ice") || $0.contains("shaved") }) {
            return "かき氷"
        }
        return nil
    }

    // MARK: - 色ユーティリティ(hex→RGB補間)

    private static func rgbComponents(of hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(hex: hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// base を toward へ amount(0...1)だけ寄せた色の hex を返す
    private static func blendHex(base: String, toward: String, amount: CGFloat) -> String {
        let from = rgbComponents(of: base)
        let to = rgbComponents(of: toward)
        let t = max(0, min(1, amount))
        let mixed = UIColor(
            red: from.r + (to.r - from.r) * t,
            green: from.g + (to.g - from.g) * t,
            blue: from.b + (to.b - from.b) * t,
            alpha: 1
        )
        return mixed.hexString
    }

    private static func isBluish(_ hex: String) -> Bool {
        let c = rgbComponents(of: hex)
        return c.b > 0.32 && c.b > c.r + 0.06 && c.b >= c.g
    }

    private static func isOrangish(_ hex: String) -> Bool {
        let c = rgbComponents(of: hex)
        return c.r > 0.45 && c.r > c.b + 0.15 && c.g > c.b && c.g < c.r
    }
}
