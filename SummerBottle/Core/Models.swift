//
//  Models.swift
//  SummerBottle
//
//  ドメインモデル定義。全モジュールが共有する「契約」。
//

import Foundation
import SwiftUI

// MARK: - 天気

enum WeatherKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case sunny      // 晴れ
    case cloudy     // 曇り
    case rain       // 雨
    case shower     // 夕立
    case stormy     // 台風前

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunny: "晴れ"
        case .cloudy: "曇り"
        case .rain: "雨"
        case .shower: "夕立"
        case .stormy: "台風前"
        }
    }

    var symbolName: String {
        switch self {
        case .sunny: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .shower: "cloud.bolt.rain.fill"
        case .stormy: "wind"
        }
    }
}

// MARK: - 時間帯

enum TimeOfDay: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning    // 朝
    case daytime    // 昼
    case evening    // 夕方
    case night      // 夜

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: "朝"
        case .daytime: "昼"
        case .evening: "夕方"
        case .night: "夜"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .daytime: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    /// 時刻から時間帯を推定する
    static func estimate(from date: Date) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<10: return .morning
        case 10..<16: return .daytime
        case 16..<19: return .evening
        default: return .night
        }
    }
}

// MARK: - 思い出の種類

enum MemoryType: String, Codable, CaseIterable, Identifiable, Hashable {
    case sea        // 海
    case trip       // 旅行
    case festival   // 夏祭り
    case fireworks  // 花火
    case drive      // ドライブ
    case camp       // キャンプ
    case park       // 公園
    case cityWalk   // 街歩き
    case meal       // 食事
    case ordinary   // 何気ない一日
    case other      // その他

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sea: "海"
        case .trip: "旅行"
        case .festival: "夏祭り"
        case .fireworks: "花火"
        case .drive: "ドライブ"
        case .camp: "キャンプ"
        case .park: "公園"
        case .cityWalk: "街歩き"
        case .meal: "食事"
        case .ordinary: "何気ない一日"
        case .other: "その他"
        }
    }

    var symbolName: String {
        switch self {
        case .sea: "water.waves"
        case .trip: "airplane"
        case .festival: "party.popper.fill"
        case .fireworks: "fireworks"
        case .drive: "car.fill"
        case .camp: "tent.fill"
        case .park: "tree.fill"
        case .cityWalk: "building.2.fill"
        case .meal: "fork.knife"
        case .ordinary: "cup.and.saucer.fill"
        case .other: "sparkles"
        }
    }
}

// MARK: - ボトルの種類

enum BottleType: String, Codable, CaseIterable, Identifiable, Hashable {
    case standard   // スタンダードボトル
    case round      // 丸型ボトル
    case mini       // 小瓶
    case lantern    // ランタンボトル
    case drift      // 漂流瓶
    case soda       // 炭酸瓶

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "スタンダードボトル"
        case .round: "丸型ボトル"
        case .mini: "小瓶"
        case .lantern: "ランタンボトル"
        case .drift: "漂流瓶"
        case .soda: "炭酸瓶"
        }
    }

    var blurb: String {
        switch self {
        case .standard: "最も基本的な透明瓶"
        case .round: "広い風景や海を見せるのに向いている"
        case .mini: "一枚の写真や短い記録向け"
        case .lantern: "夜・花火・夏祭り向け。内部が発光する"
        case .drift: "海や旅行向け。コルク栓と古いラベル付き"
        case .soda: "ラムネをイメージした夏限定デザイン"
        }
    }
}

// MARK: - シーン内オブジェクト

enum SceneObjectType: String, Codable, CaseIterable, Identifiable, Hashable {
    case cloud          // 入道雲・雲
    case fireworks      // 花火
    case mountain       // 山
    case stall          // 夏祭りの屋台
    case lanternString  // 提灯
    case torii          // 鳥居
    case watermelon     // スイカ
    case shavedIce      // かき氷
    case parasol        // ビーチパラソル
    case building       // 建物
    case photoCard      // フォトカード
    case table          // 小さなテーブル
    case food           // 料理模型
    case tree           // 木
    case bench          // ベンチ
    case streetLight    // 街灯
    case pool           // プール
    case floatRing      // 浮き輪
    case tent           // テント
    case campfire       // 焚き火
    case palmTree       // ヤシの木
    case boat           // 小舟
    case shell          // 貝殻
    case grass          // 芝生

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloud: "入道雲"
        case .fireworks: "花火"
        case .mountain: "山"
        case .stall: "屋台"
        case .lanternString: "提灯"
        case .torii: "鳥居"
        case .watermelon: "スイカ"
        case .shavedIce: "かき氷"
        case .parasol: "ビーチパラソル"
        case .building: "建物"
        case .photoCard: "フォトカード"
        case .table: "テーブル"
        case .food: "料理"
        case .tree: "木"
        case .bench: "ベンチ"
        case .streetLight: "街灯"
        case .pool: "プール"
        case .floatRing: "浮き輪"
        case .tent: "テント"
        case .campfire: "焚き火"
        case .palmTree: "ヤシの木"
        case .boat: "小舟"
        case .shell: "貝殻"
        case .grass: "芝生"
        }
    }
}

// MARK: - パーティクル

enum ParticleKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case none       // なし
    case splash     // 水しぶき
    case sand       // 砂粒
    case sparks     // 花火の光
    case fireflies  // 蛍
    case stars      // 星
    case petals     // 花びら
    case bubbles    // シャボン玉

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "なし"
        case .splash: "水しぶき"
        case .sand: "砂粒"
        case .sparks: "花火の光"
        case .fireflies: "蛍"
        case .stars: "星"
        case .petals: "花びら"
        case .bubbles: "シャボン玉"
        }
    }
}

// MARK: - 環境音

enum SoundscapeKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case waves          // 波音
    case cicadas        // セミ
    case fireworks      // 花火
    case festival       // 祭り囃子
    case wind           // 風
    case nightInsects   // 夜の虫
    case silence        // 無音

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waves: "波音"
        case .cicadas: "セミ"
        case .fireworks: "花火"
        case .festival: "祭り囃子"
        case .wind: "風"
        case .nightInsects: "夜の虫"
        case .silence: "無音"
        }
    }
}

// MARK: - 写真解析結果

/// 写真から検出される要素
enum PhotoElement: String, Codable, CaseIterable, Hashable {
    case sea, sky, mountain, city, fireworks, food, person, animal
    case indoor, outdoor, pool, park, festival, sunset, night, beach

    var displayName: String {
        switch self {
        case .sea: "海"
        case .sky: "空"
        case .mountain: "山"
        case .city: "街"
        case .fireworks: "花火"
        case .food: "食べ物"
        case .person: "人物"
        case .animal: "動物"
        case .indoor: "屋内"
        case .outdoor: "屋外"
        case .pool: "プール"
        case .park: "公園"
        case .festival: "夏祭り"
        case .sunset: "夕焼け"
        case .night: "夜"
        case .beach: "砂浜"
        }
    }
}

struct PhotoAnalysis: Codable, Hashable {
    /// 検出された要素
    var elements: Set<PhotoElement> = []
    /// 写真から推定した時間帯(EXIF or 画調)
    var timeOfDay: TimeOfDay?
    /// 主な色(hex文字列 "#RRGGBB"、多い順に最大5つ)
    var dominantColorHexes: [String] = []
    /// 夏らしい物体のラベル(Vision分類の生ラベル)
    var summerObjects: [String] = []
    /// EXIFの撮影日時
    var capturedAt: Date?
}

// MARK: - シーン構成

/// シーン内に配置される1つのミニチュア。
/// position は正規化座標: x/z は瓶内半径を1とした [-1, 1]、y は瓶内高さを1とした [0, 1]。
/// 実寸へのマッピングは BottleSceneController が行う。
struct SceneObject: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var type: SceneObjectType
    var position: SIMD3<Float> = .zero
    /// Y軸回転(ラジアン)
    var rotationY: Float = 0
    /// 相対スケール(1が標準)
    var scale: Float = 1
    /// photoCard のときのみ: 対応する BottlePhoto.id
    var photoID: UUID?
}

/// ボトル1本分の3Dシーン構成。自動生成後もユーザーが編集できる。
struct SceneConfig: Codable, Hashable {
    var bottleType: BottleType = .standard
    var timeOfDay: TimeOfDay = .daytime
    var weather: WeatherKind = .sunny
    /// 空の色(hex)。時間帯のプリセットから初期化されるが編集可能。
    var skyColorHex: String = "#7EC8E3"
    /// 海の色(hex)
    var seaColorHex: String = "#2E8BC0"
    /// 海を入れるか
    var hasSea: Bool = true
    /// 砂の量 0...1(0で砂なし)
    var sandAmount: Double = 0.4
    /// ラベルに表示する文(自動生成後、編集可能)
    var labelText: String = ""
    /// 常時漂うパーティクル/シェイク時の演出
    var particle: ParticleKind = .none
    /// 栓を開けたときのプリセット環境音(録音がある場合はそちらを優先)
    var soundscape: SoundscapeKind = .waves
    /// 配置されるミニチュア
    var objects: [SceneObject] = []
}

// MARK: - ボトル(保存単位)

struct BottlePhoto: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// メディアディレクトリ内のファイル名(例: "<id>.jpg")
    var fileName: String
    var displayOrder: Int
    var analysis: PhotoAnalysis?
}

enum AudioType: String, Codable, Hashable {
    case recorded   // その日に録音した音
    case preset     // プリセット環境音
}

struct BottleAudio: Codable, Hashable {
    /// recorded のときのみ: メディアディレクトリ内のファイル名
    var fileName: String?
    var duration: TimeInterval = 0
    var type: AudioType = .preset
    var preset: SoundscapeKind?
    /// 人の声を含む録音か(登録前の確認済みフラグ)
    var containsVoice: Bool = false
}

struct Bottle: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    /// 思い出の日付
    var memoryDate: Date
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var memoryType: MemoryType?
    /// 一言
    var comment: String?
    /// 一緒にいた人の名前
    var companions: [String] = []
    var isFavorite: Bool = false
    var sceneConfig: SceneConfig = SceneConfig()
    var photos: [BottlePhoto] = []
    var audio: BottleAudio?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 便利アクセサ
    var bottleType: BottleType { sceneConfig.bottleType }
    var weather: WeatherKind { sceneConfig.weather }
    var timeOfDay: TimeOfDay { sceneConfig.timeOfDay }

    /// 棚の色別表示に使う代表色(先頭写真の主色 → なければ空色)
    var representativeColorHex: String {
        photos.first?.analysis?.dominantColorHexes.first ?? sceneConfig.skyColorHex
    }
}

// MARK: - 作成フローの下書き

/// 写真選択〜保存までの作成フロー全体で共有する下書き状態。
@MainActor
@Observable
final class BottleDraft {
    var title: String = ""
    var memoryDate: Date = Date()
    var locationName: String = ""
    var latitude: Double?
    var longitude: Double?
    var memoryType: MemoryType?
    var comment: String = ""
    /// カンマ・読点区切りで入力された名前
    var companionsText: String = ""
    /// 手動で選んだ天気(nilなら自動=晴れ)
    var weatherOverride: WeatherKind?
    /// 手動で選んだ時間帯(nilなら写真から自動判定)
    var timeOverride: TimeOfDay?

    /// 選択済み写真(1〜10枚)。data は縮小済みJPEG。
    var photos: [DraftPhoto] = []

    /// 自動構成の結果(プレビュー・編集ステップで使用)
    var sceneConfig: SceneConfig?

    /// 録音した音声(あれば)
    var recordedAudioURL: URL?
    var recordedDuration: TimeInterval = 0
    var recordedContainsVoice: Bool = false

    var companions: [String] {
        companionsText
            .split(whereSeparator: { ",、 ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    struct DraftPhoto: Identifiable, Hashable {
        var id: UUID = UUID()
        var data: Data
        var analysis: PhotoAnalysis?
    }
}
