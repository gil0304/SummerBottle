//
//  HomeShelfView.swift
//  SummerBottle
//
//  ホーム「思い出の棚」。木目の棚にボトルのサムネイルが並ぶ。
//  NavigationStack の内側で表示される(このビュー自身はStackを作らない)。
//

import SwiftUI
import UIKit

// MARK: - 並び替え / 絞り込み

private enum ShelfArrangement: String, CaseIterable, Identifiable {
    case byDate
    case byMonth
    case byPlace
    case byType
    case byColor
    case favoritesOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byDate: "日付順"
        case .byMonth: "月別"
        case .byPlace: "場所別"
        case .byType: "思い出の種類別"
        case .byColor: "色別"
        case .favoritesOnly: "お気に入りのみ"
        }
    }

    var symbolName: String {
        switch self {
        case .byDate: "clock"
        case .byMonth: "calendar"
        case .byPlace: "mappin.and.ellipse"
        case .byType: "tag"
        case .byColor: "paintpalette"
        case .favoritesOnly: "heart"
        }
    }
}

/// 色別分類(representativeColorHex の色相で分ける)
private enum ShelfHueBucket: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "赤"
        case .orange: "橙"
        case .yellow: "黄"
        case .green: "緑"
        case .blue: "青"
        case .purple: "紫"
        case .other: "その他"
        }
    }

    static func classify(hex: String) -> ShelfHueBucket {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(hex: hex).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // 彩度・明度が低すぎる色は「その他」
        guard saturation >= 0.12, brightness >= 0.08 else { return .other }
        let degrees = hue * 360
        switch degrees {
        case 0..<15, 345...360: return .red
        case 15..<45: return .orange
        case 45..<75: return .yellow
        case 75..<165: return .green
        case 165..<255: return .blue
        case 255..<345: return .purple
        default: return .other
        }
    }
}

// MARK: - セクション / 段

private struct HomeShelfSection: Identifiable {
    let id: String
    let title: String?
    let bottles: [Bottle]
}

private struct HomeShelfRow: Identifiable {
    let id: String
    let bottles: [Bottle]
}

/// 棚まわりの配色(木の上に置くので固定色。ダークモードでも同じ見た目で破綻しない)
private enum HomeShelfPalette {
    static let ink = Color(hex: "#3B2A1A")
    static let tagPaper = Color(hex: "#F6E8C8")
    static let tagInk = Color(hex: "#5A4127")
    static let boardTop = Color(hex: "#C29A72")
    static let boardMid = Color(hex: "#9A7350")
    static let boardBottom = Color(hex: "#7C5B3E")
    static let wallTop = Color(hex: "#C59C74")
    static let wallBottom = Color(hex: "#8E6A49")
}

// MARK: - ホーム画面

struct HomeShelfView: View {
    @Environment(BottleStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var arrangement: ShelfArrangement = .byDate
    @State private var pendingDelete: Bottle?

    init() {}

    var body: some View {
        Group {
            if store.bottles.isEmpty {
                emptyState
            } else {
                shelfList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(wallBackground)
        .safeAreaInset(edge: .bottom) { createTodayButton }
        .navigationTitle("思い出の棚")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("並び替え・絞り込み", selection: $arrangement) {
                        ForEach(ShelfArrangement.allCases) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                } label: {
                    Label("並び替え", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .confirmationDialog(
            "このボトルを削除しますか?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { bottle in
            Button("削除する", role: .destructive) {
                Haptics.medium()
                store.delete(bottle.id)
                pendingDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingDelete = nil
            }
        } message: { bottle in
            Text("「\(bottle.title)」の写真や音も削除されます。この操作は取り消せません。")
        }
    }

    // MARK: 背景(木目の壁)

    private var wallBackground: some View {
        LinearGradient(
            stops: [
                .init(color: HomeShelfPalette.wallTop, location: 0.0),
                .init(color: AppTheme.shelfWood, location: 0.45),
                .init(color: HomeShelfPalette.wallBottom, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom)
        .overlay(
            // 木目風のうっすらした縦筋
            HStack(spacing: 56) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .ignoresSafeArea()
    }

    // MARK: 棚の一覧

    private var shelfList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(sections) { section in
                    if let title = section.title {
                        sectionTag(title)
                            .padding(.top, 22)
                    }
                    if section.bottles.isEmpty {
                        emptySectionNote
                    } else {
                        ForEach(rows(for: section)) { row in
                            shelfRow(row.bottles)
                                .padding(.top, 14)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    /// セクション内のボトルを1段あたり最大6本に分割する(段ごとに横スクロール)
    private func rows(for section: HomeShelfSection) -> [HomeShelfRow] {
        let perRow = 6
        var result: [HomeShelfRow] = []
        var index = 0
        while index < section.bottles.count {
            let end = min(index + perRow, section.bottles.count)
            result.append(HomeShelfRow(
                id: "\(section.id)-row\(index)",
                bottles: Array(section.bottles[index..<end])))
            index = end
        }
        return result
    }

    /// 棚1段: 横スクロールのボトル列 + 棚板 + 棚板の影
    private func shelfRow(_ bottles: [Bottle]) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(bottles) { bottle in
                        shelfCell(bottle)
                    }
                }
                .padding(.horizontal, 18)
            }
            shelfBoard
        }
    }

    /// 棚板(木目の縦グラデ)+ 壁に落ちる影
    private var shelfBoard: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            HomeShelfPalette.boardTop,
                            HomeShelfPalette.boardMid,
                            HomeShelfPalette.boardBottom,
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(height: 13)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.28), Color.black.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(height: 12)
        }
    }

    /// ボトル1本分のセル(サムネイル + タイトル + 日付)
    private func shelfCell(_ bottle: Bottle) -> some View {
        Button {
            Haptics.tap()
            router.open(.viewer(bottle.id))
        } label: {
            VStack(spacing: 5) {
                BottleThumbnailView(bottle: bottle, height: 140)
                VStack(spacing: 1) {
                    Text(bottle.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeShelfPalette.ink)
                        .lineLimit(1)
                    Text(bottle.memoryDate.shortDateString)
                        .font(.caption2)
                        .foregroundStyle(HomeShelfPalette.ink.opacity(0.65))
                }
                .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuItems(for: bottle)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for bottle: Bottle) -> some View {
        Button {
            Haptics.tap()
            store.toggleFavorite(bottle.id)
        } label: {
            Label(
                bottle.isFavorite ? "お気に入りから外す" : "お気に入りに追加",
                systemImage: bottle.isFavorite ? "heart.slash" : "heart")
        }
        Button {
            router.open(.edit(bottle.id))
        } label: {
            Label("編集", systemImage: "slider.horizontal.3")
        }
        Button {
            router.open(.export(bottle.id))
        } label: {
            Label("書き出し", systemImage: "square.and.arrow.up")
        }
        Button {
            router.open(.ar(bottle.id))
        } label: {
            Label("ARで表示", systemImage: "arkit")
        }
        Divider()
        Button(role: .destructive) {
            pendingDelete = bottle
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    /// 棚の上に掛かる小さな札風のセクションヘッダ
    private func sectionTag(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(HomeShelfPalette.tagInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(HomeShelfPalette.tagPaper)
                    .shadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0, y: 1)
            )
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptySectionNote: some View {
        Text("該当するボトルはまだありません")
            .font(.footnote)
            .foregroundStyle(HomeShelfPalette.ink.opacity(0.6))
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
    }

    // MARK: セクション計算

    private var sections: [HomeShelfSection] {
        let bottles = store.bottles
        switch arrangement {
        case .byDate:
            return [HomeShelfSection(id: "all", title: nil, bottles: bottles)]

        case .favoritesOnly:
            return [HomeShelfSection(
                id: "favorites",
                title: "お気に入り",
                bottles: bottles.filter { $0.isFavorite })]

        case .byMonth:
            var keys: [Date] = []
            var groups: [Date: [Bottle]] = [:]
            let calendar = Calendar.current
            for bottle in bottles {
                let comps = calendar.dateComponents([.year, .month], from: bottle.memoryDate)
                let key = calendar.date(from: comps) ?? bottle.memoryDate
                if groups[key] == nil { keys.append(key) }
                groups[key, default: []].append(bottle)
            }
            return keys.map { key in
                HomeShelfSection(
                    id: "month-\(Int(key.timeIntervalSince1970))",
                    title: key.yearMonthString,
                    bottles: groups[key] ?? [])
            }

        case .byPlace:
            var keys: [String] = []
            var groups: [String: [Bottle]] = [:]
            for bottle in bottles {
                let name: String
                if let location = bottle.locationName, !location.isEmpty {
                    name = location
                } else {
                    name = "場所なし"
                }
                if groups[name] == nil { keys.append(name) }
                groups[name, default: []].append(bottle)
            }
            // 「場所なし」は最後に回す
            if let index = keys.firstIndex(of: "場所なし"), index != keys.count - 1 {
                keys.remove(at: index)
                keys.append("場所なし")
            }
            return keys.map { key in
                HomeShelfSection(id: "place-\(key)", title: key, bottles: groups[key] ?? [])
            }

        case .byType:
            var result: [HomeShelfSection] = []
            for type in MemoryType.allCases {
                let matched = bottles.filter { $0.memoryType == type }
                if !matched.isEmpty {
                    result.append(HomeShelfSection(
                        id: "type-\(type.rawValue)",
                        title: type.displayName,
                        bottles: matched))
                }
            }
            let untyped = bottles.filter { $0.memoryType == nil }
            if !untyped.isEmpty {
                result.append(HomeShelfSection(id: "type-none", title: "未分類", bottles: untyped))
            }
            return result

        case .byColor:
            var result: [HomeShelfSection] = []
            for bucket in ShelfHueBucket.allCases {
                let matched = bottles.filter {
                    ShelfHueBucket.classify(hex: $0.representativeColorHex) == bucket
                }
                if !matched.isEmpty {
                    result.append(HomeShelfSection(
                        id: "color-\(bucket.rawValue)",
                        title: bucket.title,
                        bottles: matched))
                }
            }
            return result
        }
    }

    // MARK: 「今日を瓶に入れる」ボタン

    private var createTodayButton: some View {
        Button {
            Haptics.medium()
            router.showCreate = true
        } label: {
            HStack(spacing: 10) {
                ShelfBottleSilhouette(type: .drift)
                    .fill(Color.white)
                    .frame(width: 13, height: 26)
                Text("今日を瓶に入れる")
                    .font(.headline)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.coral, AppTheme.sunset],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .shadow(color: AppTheme.coral.opacity(0.55), radius: 9, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: 空状態

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            emptyBottleIllustration
            Text("最初の夏を閉じ込めよう")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeShelfPalette.ink)
            Text("写真を選ぶだけで、その日の空気が\n小さなガラス瓶の中によみがえります。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(HomeShelfPalette.ink.opacity(0.7))
            Button {
                Haptics.medium()
                router.showCreate = true
            } label: {
                Label("ボトルを作る", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.coral))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    /// SwiftUI図形で描く大きな空瓶
    private var emptyBottleIllustration: some View {
        let shape = ShelfBottleSilhouette(type: .standard)
        return ZStack {
            ZStack {
                shape.fill(AppTheme.glassTint.opacity(0.30))
                // 底の砂
                Ellipse()
                    .fill(AppTheme.sand.opacity(0.9))
                    .frame(width: 96, height: 34)
                    .offset(y: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .offset(x: 8, y: -6)
            }
            .clipShape(shape)
            shape.stroke(Color.white.opacity(0.85), lineWidth: 2)
            // ガラスのハイライト
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 7, height: 56)
                .rotationEffect(.degrees(7))
                .offset(x: -26, y: -20)
            // コルク
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "#A97B50"))
                .frame(width: 34, height: 16)
                .offset(y: -86)
        }
        .frame(width: 108, height: 185)
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 4)
    }
}
