# Summer Bottle

**夏の一日を、小さな瓶の中に閉じ込める。**

その日に撮影した写真・場所・天気・時間・一言から、夏の思い出を表現した3Dボトルを生成するiPhoneアプリ。生成されたボトルは回転・拡大・傾け・シェイクで鑑賞でき、栓を開けるとその日の環境音と一言が再生される。

## 動作環境

- iOS 26 以上 / iPhone(縦画面)
- Xcode 26 でビルド
- 外部パッケージ依存なし(システムフレームワークのみ)

## アーキテクチャ

```
SummerBottle/
├── Core/                 # 共有基盤(全モジュールの契約)
│   ├── Models.swift      #   ドメインモデル(Bottle, SceneConfig, 各enum)
│   ├── BottleStore.swift #   ローカル永続化(JSON + メディアファイル)
│   ├── AppRouter.swift   #   画面遷移
│   └── Support.swift     #   テーマ・色hex・画像・ハプティクス
├── App/RootView.swift    # タブ構成とルーティング
├── Features/
│   ├── Home/             # 思い出の棚(ホーム)
│   ├── Create/           # 作成フロー(写真→情報→解析→プレビュー→保存)+編集
│   ├── Analysis/         # Vision写真解析 + シーン自動構成ルール
│   ├── Bottle3D/         # RealityKit: 瓶・ミニチュア・パーティクル
│   ├── Viewer/           # 3D鑑賞(回転・傾き・シェイク・開栓)
│   ├── AR/               # AR配置・撮影
│   ├── Calendar/         # カレンダー
│   ├── Export/           # 静止画・ループ動画・ポストカード書き出し
│   ├── Audio/            # プロシージャル環境音・録音
│   ├── Onboarding/
│   └── Settings/
├── Sync/                 # Supabase同期(URLSession直、SDK不使用)
└── supabase/migrations/  # スキーマSQL(RLS込み)
```

### 設計上のポイント

- **AIは分類、3Dは組み立て**: 写真はVisionでオンデバイス解析し、事前定義の3Dパーツ
  (プリミティブから生成するミニチュア)を自動構成ルールで組み合わせる。
  毎回安定した品質で生成でき、元写真が端末外のAI学習に使われることもない。
- **正規化シーン座標**: `SceneObject.position` は瓶内半径・高さを1とした正規化座標。
  瓶の形が変わっても同じ構成が破綻しない。
- **ローカルファースト**: 保存済みボトルはオフラインで閲覧可能。Supabase同期は
  設定画面でURL/キーを入れたときだけ有効になる(セットアップは docs/SUPABASE.md)。
- **環境音はプロシージャル生成**: 波・セミ・花火・祭り囃子・風・夜の虫を
  PCM合成で生成(音声アセット不要)。録音は最大15秒、人の声を含む場合は確認あり。

## モジュール契約

並行開発のための各モジュールの公開インターフェースは [docs/CONTRACTS.md](docs/CONTRACTS.md) に固定している。

## Supabase同期のセットアップ

[docs/SUPABASE.md](docs/SUPABASE.md) を参照。
