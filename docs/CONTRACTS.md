# Summer Bottle モジュール契約書

このドキュメントは各機能モジュールの**公開インターフェース**を固定する。
モジュール実装者はここに書かれたシグネチャを**一字一句違わず**実装すること。
他モジュールを参照するときも、ここに書かれたシグネチャだけを前提にすること。

## ビルド環境(全員必読)

- iOS 26.0 / Xcode 26.0.1 / Swift 5 言語モード
- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor**: 何も書かなければ型・関数は暗黙に @MainActor。
  バックグラウンド処理をする関数だけ `nonisolated` を付ける。
- SWIFT_APPROACHABLE_CONCURRENCY = YES
- 外部パッケージ禁止。システムフレームワークのみ(SwiftUI, RealityKit, ARKit, Vision,
  PhotosUI, CoreMotion, AVFoundation, CoreLocation, ReplayKit, ImageIO 等)。
- ファイルは PBXFileSystemSynchronizedRootGroup により自動でターゲットに含まれる。
  `SummerBottle/` 配下に置くだけでよい。pbxproj は編集禁止。
- UIテキストはすべて日本語。
- Info.plist キー(カメラ/マイク/位置情報/写真追加)は設定済み。追加不要。
- 縦画面(Portrait)のみ。

## 共通ルール

1. **自分の担当ディレクトリ以外のファイルを作成・変更しない。**
   特に `Core/`, `App/`, `SummerBottleApp.swift`, `project.pbxproj` は変更禁止。
2. **グローバルな extension を書かない。** 必要なら `fileprivate extension` にする。
   (Color(hex:), 日付整形などは Core/Support.swift に既にある。重複定義するとビルドが壊れる)
3. トップレベルの型名にはモジュール接頭辞を付けるか、契約書で指定された名前を使う。
   契約書にない補助型は `private` / `fileprivate` にするか、明確に固有な名前を付ける。
4. 確信のないAPIは使わず、確実に存在する単純なAPIで代替する。ビルドが通ることが最優先。
5. シミュレータで動かない機能(AR、カメラ、モーション)は機能チェックをして
   優雅にフォールバックする。

## Core が提供するもの(実装済み・変更禁止)

### Models.swift
- `enum WeatherKind: String, Codable, CaseIterable, Identifiable` — sunny/cloudy/rain/shower/stormy。`displayName`, `symbolName`
- `enum TimeOfDay: String, Codable, CaseIterable, Identifiable` — morning/daytime/evening/night。`displayName`, `symbolName`, `static func estimate(from date: Date) -> TimeOfDay`
- `enum MemoryType: String, Codable, CaseIterable, Identifiable` — sea/trip/festival/fireworks/drive/camp/park/cityWalk/meal/ordinary/other。`displayName`, `symbolName`
- `enum BottleType: String, Codable, CaseIterable, Identifiable` — standard/round/mini/lantern/drift/soda。`displayName`, `blurb`
- `enum SceneObjectType: String, Codable, CaseIterable, Identifiable` — cloud/fireworks/mountain/stall/lanternString/torii/watermelon/shavedIce/parasol/building/photoCard/table/food/tree/bench/streetLight/pool/floatRing/tent/campfire/palmTree/boat/shell/grass。`displayName`
- `enum ParticleKind: String, Codable, CaseIterable, Identifiable` — none/splash/sand/sparks/fireflies/stars/petals/bubbles。`displayName`
- `enum SoundscapeKind: String, Codable, CaseIterable, Identifiable` — waves/cicadas/fireworks/festival/wind/nightInsects/silence。`displayName`
- `enum PhotoElement: String, Codable, CaseIterable` — sea/sky/mountain/city/fireworks/food/person/animal/indoor/outdoor/pool/park/festival/sunset/night/beach。`displayName`
- `struct PhotoAnalysis: Codable, Hashable` — `elements: Set<PhotoElement>`, `timeOfDay: TimeOfDay?`, `dominantColorHexes: [String]`, `summerObjects: [String]`, `capturedAt: Date?`
- `struct SceneObject: Codable, Identifiable, Hashable` — `id: UUID`, `type`, `position: SIMD3<Float>`(**正規化座標**: x/z は瓶内半径=1 の [-1,1]、y は瓶内高さ=1 の [0,1])、`rotationY: Float`(ラジアン)、`scale: Float`、`photoID: UUID?`(photoCardのみ)
- `struct SceneConfig: Codable, Hashable` — `bottleType`, `timeOfDay`, `weather`, `skyColorHex: String`, `seaColorHex: String`, `hasSea: Bool`, `sandAmount: Double`(0...1)、`labelText: String`, `particle: ParticleKind`, `soundscape: SoundscapeKind`, `objects: [SceneObject]`
- `struct BottlePhoto: Codable, Identifiable, Hashable` — `id: UUID`, `fileName: String`, `displayOrder: Int`, `analysis: PhotoAnalysis?`
- `enum AudioType: String, Codable` — recorded/preset
- `struct BottleAudio: Codable, Hashable` — `fileName: String?`, `duration: TimeInterval`, `type: AudioType`, `preset: SoundscapeKind?`, `containsVoice: Bool`
- `struct Bottle: Codable, Identifiable, Hashable` — `id: UUID`, `title`, `memoryDate: Date`, `locationName: String?`, `latitude/longitude: Double?`, `memoryType: MemoryType?`, `comment: String?`, `companions: [String]`, `isFavorite: Bool`, `sceneConfig: SceneConfig`, `photos: [BottlePhoto]`, `audio: BottleAudio?`, `createdAt/updatedAt: Date`。便利アクセサ `bottleType`, `weather`, `timeOfDay`, `representativeColorHex: String`
- `@MainActor @Observable final class BottleDraft` — 作成フローの下書き。`title`, `memoryDate`, `locationName: String`, `latitude/longitude: Double?`, `memoryType: MemoryType?`, `comment: String`, `companionsText: String`, `companions: [String]`(算出)、`weatherOverride: WeatherKind?`, `timeOverride: TimeOfDay?`, `photos: [DraftPhoto]`, `sceneConfig: SceneConfig?`, `recordedAudioURL: URL?`, `recordedDuration: TimeInterval`, `recordedContainsVoice: Bool`。`BottleDraft.DraftPhoto` は `id: UUID`, `data: Data`, `analysis: PhotoAnalysis?`

### BottleStore.swift (`@MainActor @Observable final class BottleStore`、`@Environment(BottleStore.self)` で取得)
- `bottles: [Bottle]`(memoryDate降順)
- `func bottle(id: Bottle.ID) -> Bottle?`
- `func add(_ bottle: Bottle, photoDatas: [UUID: Data], audioSourceURL: URL?)`
- `func update(_ bottle: Bottle)` / `func delete(_ id: Bottle.ID)` / `func toggleFavorite(_ id: Bottle.ID)`
- `func replaceAll(with: [Bottle])` / `func upsertFromRemote(_ bottle: Bottle)`(同期用)
- `var lastLocalChange: Date`
- `func mediaDirectory(for bottleID: Bottle.ID) -> URL`
- `func photoURL(bottleID: Bottle.ID, fileName: String) -> URL`
- `func audioURL(for bottle: Bottle) -> URL?`
- `func photoData(bottleID: Bottle.ID, fileName: String) -> Data?`
- `func photoCGImages(for bottle: Bottle, maxPixel: CGFloat = 1024) -> [UUID: CGImage]`

### AppRouter.swift (`@MainActor @Observable final class AppRouter`、`@Environment(AppRouter.self)` で取得)
- `selectedTab: AppTab`(shelf/calendar/settings)
- `showCreate: Bool` — trueで作成フローが全画面表示される
- `func open(_ route: Route)` — `Route` は `.viewer(Bottle.ID)` / `.edit(Bottle.ID)` / `.export(Bottle.ID)` / `.ar(Bottle.ID)`

### Support.swift
- `enum AppTheme` — `ocean/deepSea/sand/coral/sunset/nightNavy/shelfWood/glassTint: Color`、`static func skyGradient(for: TimeOfDay) -> LinearGradient`、`static func defaultSkyHex(for: TimeOfDay) -> String`、`static func defaultSeaHex(for: TimeOfDay) -> String`
- `Color(hex: String)` / `color.hexString` / `UIColor(hex:)` / `uiColor.hexString`
- `enum ImageUtil`(全て nonisolated static)— `downscaledJPEGData(from: Data, maxPixel: CGFloat = 2048, quality: CGFloat = 0.85) -> Data?`、`cgImage(from: Data, maxPixel: CGFloat = 1024) -> CGImage?`、`cgImage(contentsOf: URL, maxPixel: CGFloat = 1024) -> CGImage?`、`captureDate(from: Data) -> Date?`
- `enum Haptics` — `tap()/medium()/success()`
- `Date` — `japaneseDateString`(2026年7月13日)/ `shortDateString`(7/13)/ `yearMonthString`(2026年7月)

---

## モジュール別契約

### 1. Bottle3D コア — `Features/Bottle3D/`
ファイル: `BottleSceneController.swift`, `BottleGeometry.swift`, `SceneParticles.swift`, `BottlePreview3DView.swift`

```swift
@MainActor
final class BottleSceneController {
    /// ルートエンティティ。RealityView の content や ARView のシーンへ追加する。
    let rootEntity: Entity
    init(config: SceneConfig, photos: [UUID: CGImage])
    /// 構成変更時に中身を作り直す
    func update(config: SceneConfig, photos: [UUID: CGImage])
    /// 端末の傾き(ラジアン)に応じて水面・砂・雲・光・フォトカードをわずかに動かす
    func applyTilt(pitch: Float, roll: Float)
    /// シェイク演出。config.particle(noneならシーンに合った既定)のバーストを発生させる
    func triggerShake()
    /// 栓の開閉(アニメーション付き)
    func setCorkOpen(_ open: Bool)
    private(set) var isCorkOpen: Bool
    /// タップされたエンティティがフォトカードなら対応する BottlePhoto.id を返す
    /// (エンティティ階層を親方向に遡って判定すること)
    func photoID(for entity: Entity) -> UUID?
    /// ボトル全高(メートル)。カメラ距離の目安。standardで約0.24
    var bottleHeight: Float { get }
}

/// 自己完結のプレビュー用3Dビュー。ドラッグで回転・ピンチで拡大縮小。
/// モーション連動・シェイク・音は含まない。作成フロー/編集画面/書き出しで使う。
struct BottlePreview3DView: View {
    init(config: SceneConfig, photos: [UUID: CGImage])
}
```

実装指針:
- 瓶: `MeshResource.generateCylinder/Sphere/Box` 等の組み合わせ。ガラスは
  `PhysicallyBasedMaterial` + `blending = .transparent(opacity:)`(約0.15)、roughness低。
  内容物を先に、ガラスを後に追加(描画順)。
- BottleType ごとに形状・寸法を変える(standard:円筒+首、round:球、mini:小さい円筒、
  lantern:円筒+内部PointLight、drift:円筒+コルク+古紙ラベル、soda:細長+ビー玉)。
- 内容物は正規化座標→実寸へマッピング(SceneObject.position 参照)。
- 空: 瓶の内側に skyColorHex の背景(UnlitMaterialの内向き円筒/board)。夜は星(小さな発光球)。
- 海: hasSea のとき seaColorHex の半透明スラブ。sandAmount>0 のとき砂色の底。
- ミニチュア: `MiniaturePrefabs.make(_:config:)`(契約2)を呼ぶ。photoCard タイプは
  コントローラ側で写真テクスチャ(`TextureResource(image:options:)`)+白枠の板を生成。
- ラベル: labelText と日付っぽい見た目の白い板。テクスチャは ImageRenderer で
  SwiftUI Text から生成してもよい(@MainActorなので可)。
- 天気: rain=瓶内側の水滴(小さな半透明球)、shower=暗い雲+稲光(明滅PointLight)、
  stormy=傾いた波・低い雲、cloudy=柔らかい環境光、sunny=強いDirectionalLight。
- 時間帯: morning=淡い光+薄霧(半透明板)、daytime=強い白光、evening=オレンジ光+長影、
  night=暗い環境+月/星+街や花火の光。
- パーティクル: `ParticleEmitterComponent`(iOS 18+で利用可)。ambient(常時弱く)と
  triggerShake() のバースト。ParticleKind ごとに色・速度・寿命を変える。
- コルク/栓: 瓶口の上の円錐台。setCorkOpen で上に浮いて傾くアニメーション
  (`Entity.move(to:relativeTo:duration:)`)。
- applyTilt: 水面スラブをroll方向へ微傾斜、雲・カードを微オフセット。大袈裟にしない。

### 2. ミニチュアプレファブ — `Features/Bottle3D/MiniaturePrefabs.swift`

```swift
@MainActor
enum MiniaturePrefabs {
    /// photoCard 以外の全 SceneObjectType のミニチュアを生成する。
    /// 返すEntityは原点=足元中心、高さ約0.02〜0.05m のスケール感。
    /// photoCard が渡されたら空のEntityを返してよい(コントローラが処理する)。
    static func make(_ type: SceneObjectType, config: SceneConfig) -> Entity
}
```

- プリミティブ(box/sphere/cylinder/cone/plane)+ `SimpleMaterial`/`PhysicallyBasedMaterial`/
  `UnlitMaterial` の組み合わせで、23種すべてをかわいいミニチュアとして作り込む。
  例: スイカ=緑球+濃緑縞+赤い切断面、パラソル=傾いた円錐+白赤ストライプ+棒、
  提灯=発光する小さな橙円筒を紐状に並べる、花火=放射状の細い発光棒の束、など。
- 夜(config.timeOfDay == .night)は発光を強める等、configで表情を変えてよい。

### 3. 写真解析 — `Features/Analysis/PhotoAnalyzer.swift`

```swift
enum PhotoAnalyzer {
    /// Visionで写真を解析する。メインスレッドをブロックしないこと(nonisolated)。
    nonisolated static func analyze(imageData: Data) async -> PhotoAnalysis
}
```

- `VNClassifyImageRequest` の分類ラベルを PhotoElement へマッピング
  (beach/coast/ocean→sea・beach、sky→sky、mountain→mountain、cityscape/building→city、
  fireworks→fireworks、food系→food、people→person、dog/cat/animal→animal、
  indoor/outdoor、pool、park、sunset、night 等。confidence 0.3以上を採用)。
- 主な色: 縮小画像のピクセルを集計して上位5色のhexを出す(簡易クラスタリングで可)。
- `ImageUtil.captureDate(from:)` でEXIF撮影日時→ `TimeOfDay.estimate` で時間帯。
  EXIFがなければ画像の明度・色味から昼/夕/夜を推定。
- 夏らしい物体ラベル(watermelon, ice cream等)を summerObjects に格納。
- 顔認識・個人特定はしない。

### 4. シーン自動構成 — `Features/Analysis/SceneComposer.swift`

```swift
@MainActor
enum SceneComposer {
    /// 下書き(写真解析済み)から SceneConfig を自動生成する(仕様書7章のルール)
    static func compose(draft: BottleDraft) -> SceneConfig
}
```

- 時間帯: `draft.timeOverride` → 写真の analysis.timeOfDay 多数決 → memoryDateの時刻。
- 天気: `draft.weatherOverride` → 既定 .sunny。
- 空色/海色: AppTheme.defaultSkyHex/defaultSeaHex を基準に、写真の主色があれば寄せる。
- 検出内容→オブジェクト(仕様書7.3): sea→hasSea+砂浜+(parasol,floatRing,shell)、
  fireworks→夜空+fireworks+particle .sparks、festival→lanternString+stall+torii、
  food→table+food、mountain→mountain+tree、city→building+streetLight、
  park→grass+bench+tree、pool→pool+floatRing。
- MemoryType でも補完(sea→海要素、camp→tent+campfire、drive→boat?は使わず街/山要素等)。
- BottleType 推奨: night/fireworks/festival→lantern、sea/trip→drift、写真1枚→mini、
  sea広め→round、それ以外→standard。
- ミニチュアは3〜8個。正規化座標で重ならないよう円周上に散らして配置。
- photoCard: 写真ごとに1枚(最大3枚)を目立つ位置に配置(photoID を設定)。
- particle: 夜→fireflies/stars、海→splash、祭り→sparks 等。soundscape も同様に選ぶ
  (sea→waves、festival→festival、fireworks→fireworks、夜→nightInsects、昼→cicadas)。
- labelText: タイトル・日付・場所・一言から短いラベル文を生成(テンプレートで可。
  例: "2026.7.13 江ノ島 — 波の音と、スイカの午後")。

### 5. 音 — `Features/Audio/`
ファイル: `AudioService.swift`, `PresetSoundscapes.swift`, `AudioRecorderSheet.swift`

```swift
@MainActor @Observable
final class AudioService {
    static let shared: AudioService
    private(set) var isPlaying: Bool
    func playPreset(_ kind: SoundscapeKind, loop: Bool)
    func playFile(at url: URL, loop: Bool)
    func stop()
}

/// 録音シート(最大15秒で自動停止)。波形/経過表示付き。
/// 「人の声が入っていますか?」の確認チェックを含む(仕様書10章)。
struct AudioRecorderSheet: View {
    init(onComplete: @escaping (_ url: URL, _ duration: TimeInterval, _ containsVoice: Bool) -> Void)
}
```

- プリセット環境音は**プロシージャル生成**する(アセット無し):
  PCMバッファを合成してWAVをキャッシュディレクトリへ書き出し、AVAudioPlayerで再生。
  waves=ローパスノイズのうねり、cicadas=高周波チチチのバースト、fireworks=減衰ノイズ破裂音+残響、
  festival=太鼓風パルス+笛風正弦波、wind=帯域ノイズのゆらぎ、nightInsects=コオロギ風チャープ。
  15秒ループ。生成は初回のみ(ファイルキャッシュ)。
- 録音: AVAudioRecorder(m4a)。マイク許可処理を含む。15秒で自動停止。

### 6. 作成フロー — `Features/Create/`
ファイル: `CreateFlowView.swift`, `PhotoPickStep.swift`, `InfoStep.swift`, `AnalyzeStep.swift`, `PreviewStep.swift`, `SceneEditView.swift`, `BottleEditView.swift`

```swift
/// 全画面の作成フロー。BottleDraft を内部で生成し、ステップを進める。
/// 保存時は BottleStore.add(...) → dismiss。
struct CreateFlowView: View { init() }

/// シーン編集UI(仕様書6.5の全項目)。上部にBottlePreview3DViewのライブプレビュー。
struct SceneEditView: View {
    init(config: Binding<SceneConfig>, photos: [UUID: CGImage])
}

/// 保存済みボトルの再編集画面(Route.edit から遷移)。
struct BottleEditView: View { init(bottleID: Bottle.ID) }
```

- ステップ: 写真選択(PhotosPicker、1〜10枚、`ImageUtil.downscaledJPEGData`で縮小)
  → 基本情報(タイトル必須/日付/場所+CoreLocation現在地ボタン任意/一言/一緒にいた人/
  思い出の種類チップ/天気/時間帯(自動・手動)/環境音の録音 `AudioRecorderSheet`)
  → 自動解析(`PhotoAnalyzer.analyze` を各写真に実行、進捗表示、完了後
  `SceneComposer.compose`)→ プレビュー(`BottlePreview3DView`+「編集」で SceneEditView、
  「作り直す」で再compose)→ 保存。
- 保存: Bottle を組み立て(photos は displayOrder 順、fileName は "\(photoID).jpg")、
  photoDatas: [UUID: Data]、音声があれば BottleAudio(type: .recorded, fileName: "voice.m4a")
  として `store.add(_:photoDatas:audioSourceURL:)`。録音がなければ
  BottleAudio(type: .preset, preset: config.soundscape)。
- SceneEditView で編集できる項目: ボトルの形/空の色/海の色(ColorPicker↔hex変換は
  Color(hex:)/hexString)/砂の量/時間帯/ミニチュア配置(追加・削除・位置x,zスライダ・
  回転・スケール)/フォトカード位置/ラベル文/パーティクル/環境音。

### 7. 3D鑑賞 — `Features/Viewer/`
ファイル: `BottleViewerView.swift`, `MotionManager.swift`, `PhotoDetailView.swift`

```swift
/// Route.viewer(id) から遷移。RealityView + BottleSceneController。
struct BottleViewerView: View { init(bottleID: Bottle.ID) }

/// フォトカードタップで全画面表示(ピンチズーム対応)。
struct PhotoDetailView: View { init(bottleID: Bottle.ID, photoID: UUID) }
```

- ドラッグで360度回転(Y軸+少しX)、ピンチで拡大縮小(カメラ距離 or スケール)。
- RealityView には PerspectiveCamera を追加し約0.55mの距離から注視。
- CoreMotion(CMMotionManager.deviceMotion)で `controller.applyTilt(pitch:roll:)`。
  userAcceleration の大きさ閾値でシェイク検出→ `controller.triggerShake()` + Haptics。
  シミュレータではモーション不可: `isDeviceMotionAvailable` チェック+画面ボタンで代替。
- 画面上部での上方向スワイプ→ `controller.setCorkOpen(true)` +音再生:
  録音があれば `store.audioURL(for:)` を `AudioService.shared.playFile`、
  なければ `playPreset(config.soundscape)`。同時に一言(comment)をオーバーレイ表示。
  もう一度で閉栓+停止。
- SpatialTapGesture(RealityViewのエンティティターゲット)→ `controller.photoID(for:)`
  → PhotoDetailView をfullScreenCoverで表示。
- ツールバー: お気に入り、メニュー(編集/書き出し/AR/削除)。削除は確認ダイアログ→
  `store.delete` → 戻る。編集等は `router.open(.edit(id))` など。

### 8. ホーム(思い出の棚) — `Features/Home/`
ファイル: `HomeShelfView.swift`, `BottleThumbnailView.swift`

```swift
struct HomeShelfView: View { init() }

/// 2Dのスタイライズドボトルサムネイル(SwiftUI描画、3D不使用)。カレンダーも使う。
struct BottleThumbnailView: View {
    init(bottle: Bottle, height: CGFloat)
}
```

- 木の棚(AppTheme.shelfWood のグラデ描画)にボトルが並ぶ。横スワイプで閲覧
  (横スクロール棚 or 段組み)。タップで `router.open(.viewer(id))`。
- 並び替え/絞り込みメニュー: 日付順・月別・場所別・思い出の種類別・色別・お気に入りのみ
  (セクション分け表示)。
- 「今日を瓶に入れる」ボタン(目立つ主ボタン)→ `router.showCreate = true`。
- 空状態: 初回向けの誘導。コンテキストメニュー: お気に入り/編集/書き出し/AR/削除。
- BottleThumbnailView: bottleType に応じた瓶シルエット(Path/Capsule描画)+
  representativeColorHex と skyColorHex のグラデ中身+小さな装飾。favoriteバッジ。

### 9. カレンダー — `Features/Calendar/CalendarView.swift`

```swift
struct CalendarView: View { init() }
```

- 月グリッド(月送り可)。ボトルがある日に小さな瓶アイコン(複数個は重ね+数字)。
- 日付タップ→その日のボトル一覧(シート)→タップで `router.open(.viewer(id))`。

### 10. AR — `Features/AR/ARBottleView.swift`

```swift
struct ARBottleView: View { init(bottleID: Bottle.ID) }
```

- ARView(平面検出+コーチングオーバーレイ)。タップで平面上に配置。
- 実物大(高さ約0.22m)/ミニチュア(約0.08m)切り替え。
- 「ボトルを追加」で保存済みの他ボトルも選んで複数同時配置。
- 写真撮影(arView.snapshot→フォトライブラリ保存)、動画撮影(RPScreenRecorder)。
- 割る・取り出す機能は入れない。`ARWorldTrackingConfiguration.isSupported` が false
  (シミュレータ)なら説明画面を出す。

### 11. 書き出し — `Features/Export/`
ファイル: `ExportView.swift`, `ExportRenderer.swift`

```swift
struct ExportView: View { init(bottleID: Bottle.ID) }
```

- 静止画: 正方形/9:16/16:9/透過背景/ポスター(日付・一言入り)。
  実装: ARView(cameraMode: .nonAR) をオフスクリーンで使い BottleSceneController の
  rootEntity + PerspectiveCamera を配置して `snapshot(saveToHDR:completion:)`。
  透過は単色背景スナップショット→背景色キーで除去で可。ポスターは ImageRenderer で
  スナップショット+文字を合成。
- 動画: 5〜15秒ループ。カメラが近づく→内部が動く(ゆっくり回転)→ラベルと日付表示→
  戻る、をフレーム毎スナップショットで AVAssetWriter へエンコード(H.264, 30fps, 1080x1920)。
  進捗表示必須。
- ポストカード: 表=ボトル、裏=日付・場所・一言のレイアウトを ImageRenderer で生成。
- 出力は ShareLink / UIActivityViewController で共有+フォトライブラリ保存。

### 12. オンボーディング/設定 — `Features/Onboarding/OnboardingView.swift`, `Features/Settings/SettingsView.swift`

```swift
struct OnboardingView: View { init(onFinish: @escaping () -> Void) }
struct SettingsView: View { init() }
```

- オンボーディング: 3〜4ページ(コンセプト/作り方/鑑賞・AR)。SwiftUIの図形・グラデで
  夏らしいビジュアル。最後に「はじめる」→ onFinish()。
- 設定: 同期セクション(`SyncSettingsSection()` を埋め込む — 契約13)/データ
  (ボトル数、全削除=確認付き)/プライバシー説明(元写真をAI学習に使わない・
  ソーシャルフィードなし・位置情報は任意)/オンボーディングをもう一度見る/バージョン。

### 13. Supabase同期 — `Sync/SupabaseSyncService.swift`, `Sync/SyncSettingsSection.swift`, リポジトリ直下 `supabase/migrations/001_init.sql`, `docs/SUPABASE.md`

```swift
@MainActor @Observable
final class SyncService {
    static let shared: SyncService
    var isConfigured: Bool { get }
    private(set) var isSignedIn: Bool
    private(set) var isSyncing: Bool
    private(set) var statusText: String
    func configure(urlString: String, anonKey: String)
    func requestOTP(email: String) async throws
    func verifyOTP(email: String, code: String) async throws
    func signOut()
    func syncNow(store: BottleStore) async
}

/// 設定画面のFormに埋め込むセクション(URL/キー設定、メールOTPログイン、今すぐ同期)
struct SyncSettingsSection: View { init() }
```

- 外部SDK禁止のため URLSession で直接 Supabase REST を叩く:
  GoTrue(`/auth/v1/otp`, `/auth/v1/verify`)、PostgREST(`/rest/v1/bottles` 等)、
  Storage(`/storage/v1/object/...`)。
- 未設定ならすべて何もしない(アプリはローカルのみで完全動作)。設定は UserDefaults、
  トークンは Keychain(Security framework直)へ。
- 同期方針: updatedAt 比較の双方向同期(新しい方が勝つ)。bottles行は仕様書17章の
  カラム構成(scene_config はJSON)。写真・音声は Storage バケット `bottle-media` へ
  `<user_id>/<bottle_id>/<fileName>`。
- SQL: bottles/bottle_photos/bottle_audio テーブル+RLS(user_id = auth.uid())+
  Storageバケットとポリシー。アプリ側は bottles.scene_config に objects も含めて
  保存してよい(bottle_objects テーブルも定義はしておく)。
- docs/SUPABASE.md: セットアップ手順(プロジェクト作成→SQL実行→URL/キーをアプリ設定へ)。
