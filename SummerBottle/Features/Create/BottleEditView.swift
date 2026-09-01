//
//  BottleEditView.swift
//  SummerBottle
//
//  保存済みボトルの再編集画面(Route.edit から遷移)。
//  store.bottle(id:) から sceneConfig と基本情報を @State にコピーして編集し、
//  ツールバーの「保存」で store.update → 戻る。
//  「シーン」タブに SceneEditView を埋め込み、「基本情報」タブでタイトル等を編集する。
//

import CoreGraphics
import SwiftUI

/// 保存済みボトルの再編集画面。
struct BottleEditView: View {
    @Environment(BottleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bottleID: Bottle.ID

    init(bottleID: Bottle.ID) {
        self.bottleID = bottleID
    }

    private enum EditTab: Hashable {
        case scene
        case info
    }

    @State private var isLoaded = false
    @State private var loadFailed = false
    @State private var editTab: EditTab = .scene

    // 編集用コピー
    @State private var config = SceneConfig()
    @State private var title = ""
    @State private var comment = ""
    @State private var locationName = ""
    @State private var companionsText = ""
    @State private var memoryDate = Date()
    @State private var memoryType: MemoryType?
    @State private var isFavorite = false
    @State private var photos: [UUID: CGImage] = [:]

    var body: some View {
        Group {
            if isLoaded {
                editor
            } else if loadFailed {
                ContentUnavailableView(
                    "ボトルが見つかりません",
                    systemImage: "exclamationmark.triangle",
                    description: Text("このボトルは削除された可能性があります。")
                )
            } else {
                ProgressView("読み込んでいます…")
            }
        }
        .navigationTitle("ボトルを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!isLoaded)
            }
        }
        .task {
            load()
        }
    }

    // MARK: - 編集画面本体

    private var editor: some View {
        VStack(spacing: 0) {
            Picker("編集対象", selection: $editTab) {
                Text("シーン").tag(EditTab.scene)
                Text("基本情報").tag(EditTab.info)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch editTab {
            case .scene:
                SceneEditView(config: $config, photos: photos)
            case .info:
                infoForm
            }
        }
    }

    private var infoForm: some View {
        Form {
            Section("タイトル") {
                TextField("タイトル", text: $title)
            }
            Section("一言") {
                TextField("例: 波が高くて、スイカが甘かった", text: $comment, axis: .vertical)
                    .lineLimit(1...3)
            }
            Section("場所") {
                TextField("例: 江ノ島", text: $locationName)
            }
            Section("日付") {
                DatePicker("思い出の日付", selection: $memoryDate, displayedComponents: .date)
            }
            Section("思い出の種類") {
                Picker("種類", selection: $memoryType) {
                    Text("未設定").tag(nil as MemoryType?)
                    ForEach(MemoryType.allCases) { type in
                        Label(type.displayName, systemImage: type.symbolName)
                            .tag(type as MemoryType?)
                    }
                }
            }
            Section {
                TextField("例: はるか、けんた", text: $companionsText)
            } header: {
                Text("一緒にいた人")
            } footer: {
                Text("読点やカンマで区切って複数入力できます。")
            }
            Section {
                Toggle("お気に入り", isOn: $isFavorite)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 読み込みと保存

    private func load() {
        guard !isLoaded else { return }
        guard let bottle = store.bottle(id: bottleID) else {
            loadFailed = true
            return
        }
        config = bottle.sceneConfig
        title = bottle.title
        comment = bottle.comment ?? ""
        locationName = bottle.locationName ?? ""
        companionsText = bottle.companions.joined(separator: "、")
        memoryDate = bottle.memoryDate
        memoryType = bottle.memoryType
        isFavorite = bottle.isFavorite
        photos = store.photoCGImages(for: bottle)
        isLoaded = true
    }

    private func save() {
        guard var bottle = store.bottle(id: bottleID) else {
            dismiss()
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            bottle.title = trimmedTitle
        }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        bottle.comment = trimmedComment.isEmpty ? nil : trimmedComment
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        bottle.locationName = trimmedLocation.isEmpty ? nil : trimmedLocation
        bottle.memoryDate = memoryDate
        bottle.memoryType = memoryType
        bottle.isFavorite = isFavorite
        bottle.companions = parsedCompanions
        bottle.sceneConfig = config

        store.update(bottle)
        Haptics.success()
        dismiss()
    }

    private var parsedCompanions: [String] {
        companionsText
            .split(whereSeparator: { ",、 ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
