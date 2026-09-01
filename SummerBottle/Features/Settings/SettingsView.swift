//
//  SettingsView.swift
//  SummerBottle
//
//  設定画面。同期(SyncSettingsSection)/データ管理/プライバシー説明/
//  オンボーディング再表示/アプリ情報。
//

import SwiftUI

struct SettingsView: View {
    @Environment(BottleStore.self) private var store
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = true

    /// 全削除の確認(1段階目: ダイアログ)
    @State private var showDeleteDialog = false
    /// 全削除の確認(2段階目: 最終アラート)
    @State private var showFinalDeleteAlert = false
    /// オンボーディング再表示の案内
    @State private var showOnboardingResetNote = false

    init() {}

    var body: some View {
        Form {
            // MARK: 同期(契約13: 別モジュール提供)
            SyncSettingsSection()

            // MARK: データ
            Section {
                LabeledContent("保存したボトル") {
                    Text("\(store.bottles.count)本")
                }
                Button(role: .destructive) {
                    showDeleteDialog = true
                } label: {
                    Text("すべてのボトルを削除")
                }
                .disabled(store.bottles.isEmpty)
            } header: {
                Text("データ")
            } footer: {
                Text("ボトルは端末内に保存され、オフラインでも閲覧できます。")
            }

            // MARK: プライバシー
            Section {
                privacyRow(
                    icon: "photo",
                    title: "元の写真をAIの学習に使いません",
                    detail: "写真の解析はすべてこの端末の中だけで行われます。"
                )
                privacyRow(
                    icon: "eye.slash",
                    title: "写真や音声を公開するソーシャルフィードはありません",
                    detail: "ボトルの中身はあなたのためだけの思い出です。"
                )
                privacyRow(
                    icon: "location",
                    title: "位置情報の記録は任意です",
                    detail: "場所を残したいときにだけ使われます。あとから消すこともできます。"
                )
            } header: {
                Text("プライバシー")
            }

            // MARK: オンボーディング
            Section {
                Button {
                    hasOnboarded = false
                    Haptics.tap()
                    showOnboardingResetNote = true
                } label: {
                    Label("オンボーディングをもう一度見る", systemImage: "book.pages")
                }
            } footer: {
                Text("アプリの使い方の説明をもう一度表示します。")
            }

            // MARK: アプリ情報
            Section {
                LabeledContent("バージョン") {
                    Text(versionString)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summer Bottle")
                        .font(.headline)
                        .foregroundStyle(AppTheme.deepSea)
                    Text("夏の一日を、小さな瓶の中に閉じ込める。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("アプリ情報")
            }
        }
        .navigationTitle("設定")
        // 1段階目の確認
        .confirmationDialog(
            "すべてのボトルを削除しますか?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("削除に進む", role: .destructive) {
                showFinalDeleteAlert = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存した\(store.bottles.count)本のボトルと、写真・音声がすべて削除されます。")
        }
        // 2段階目の最終確認
        .alert("本当に削除しますか?", isPresented: $showFinalDeleteAlert) {
            Button("すべて削除", role: .destructive) {
                deleteAllBottles()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。瓶の中の夏は戻ってきません。")
        }
        // オンボーディング再表示の案内
        .alert("オンボーディングを表示します", isPresented: $showOnboardingResetNote) {
            Button("OK") {}
        } message: {
            Text("アプリの最初の説明がもう一度表示されるようになりました。")
        }
    }

    // MARK: - ヘルパー

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppTheme.ocean)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func deleteAllBottles() {
        let ids = store.bottles.map(\.id)
        for id in ids {
            store.delete(id)
        }
        Haptics.success()
    }
}
