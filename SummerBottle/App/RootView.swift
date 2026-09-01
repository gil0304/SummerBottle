//
//  RootView.swift
//  SummerBottle
//
//  タブ構成(棚・カレンダー・設定)、ルート→画面のマッピング、
//  オンボーディングと作成フローの表示を担う。
//

import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("棚", systemImage: "archivebox.fill", value: AppTab.shelf) {
                NavigationStack(path: $router.shelfPath) {
                    HomeShelfView()
                        .bottleRouteDestinations()
                }
            }
            Tab("カレンダー", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack(path: $router.calendarPath) {
                    CalendarView()
                        .bottleRouteDestinations()
                }
            }
            Tab("設定", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(AppTheme.ocean)
        .fullScreenCover(isPresented: $router.showCreate) {
            CreateFlowView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasOnboarded },
            set: { hasOnboarded = !$0 }
        )) {
            OnboardingView { hasOnboarded = true }
        }
    }
}

extension View {
    /// Route → 実画面のマッピング。棚とカレンダー両方のスタックで使う。
    func bottleRouteDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .viewer(let id):
                BottleViewerView(bottleID: id)
            case .edit(let id):
                BottleEditView(bottleID: id)
            case .export(let id):
                ExportView(bottleID: id)
            case .ar(let id):
                ARBottleView(bottleID: id)
            }
        }
    }
}
