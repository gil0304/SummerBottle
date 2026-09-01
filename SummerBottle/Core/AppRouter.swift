//
//  AppRouter.swift
//  SummerBottle
//
//  画面遷移の中枢。タブ選択・ナビゲーションスタック・作成フローの表示を管理する。
//

import SwiftUI

enum AppTab: Hashable {
    case shelf      // 思い出の棚
    case calendar   // カレンダー
    case settings   // 設定
}

/// プッシュ遷移先。RootView が各ルートを実画面へマッピングする。
enum Route: Hashable {
    case viewer(Bottle.ID)      // 3D鑑賞
    case edit(Bottle.ID)        // パーツ編集
    case export(Bottle.ID)      // 書き出し
    case ar(Bottle.ID)          // AR表示
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .shelf
    var shelfPath: [Route] = []
    var calendarPath: [Route] = []
    /// 「今日を瓶に入れる」フローの表示
    var showCreate: Bool = false

    /// 現在のタブのスタックへプッシュする
    func open(_ route: Route) {
        switch selectedTab {
        case .shelf, .settings:
            selectedTab = .shelf
            shelfPath.append(route)
        case .calendar:
            calendarPath.append(route)
        }
    }

    func popToRoot() {
        shelfPath.removeAll()
        calendarPath.removeAll()
    }
}
