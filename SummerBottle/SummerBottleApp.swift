//
//  SummerBottleApp.swift
//  SummerBottle
//
//  夏の一日を、小さな瓶の中に閉じ込める。
//

import SwiftUI

@main
struct SummerBottleApp: App {
    @State private var store = BottleStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
        }
    }
}
