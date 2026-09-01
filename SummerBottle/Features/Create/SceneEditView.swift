//
//  SceneEditView.swift
//  SummerBottle
//
//  シーン編集UI(契約書6章 / 仕様書6.5)。
//  上部に BottlePreview3DView のライブプレビュー、下に編集フォーム:
//  ボトルの形/時間帯/空色・海色/海の有無/砂の量/ラベル文/パーティクル/環境音/
//  ミニチュア一覧(追加・位置・回転・スケール・削除。photoCard は移動のみ)。
//

import CoreGraphics
import SwiftUI

/// シーン編集ビュー。作成フロー(プレビューの「編集」)と BottleEditView から使う。
struct SceneEditView: View {
    @Binding var config: SceneConfig
    let photos: [UUID: CGImage]

    init(config: Binding<SceneConfig>, photos: [UUID: CGImage]) {
        self._config = config
        self.photos = photos
    }

    var body: some View {
        VStack(spacing: 0) {
            BottlePreview3DView(config: config, photos: photos)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipped()
            Divider()
            Form {
                bottleSection
                timeSection
                colorSection
                seaSection
                labelSection
                effectSection
                objectsSection
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - ボトルの形

    private var bottleSection: some View {
        Section {
            CreateChipRow(
                items: BottleType.allCases,
                selectedID: config.bottleType.id,
                title: { $0.displayName }
            ) { tapped in
                config.bottleType = tapped
                Haptics.tap()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 0))
            Text(config.bottleType.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("ボトルの形")
        }
    }

    // MARK: - 時間帯

    private var timeSection: some View {
        Section("時間帯") {
            CreateChipRow(
                items: TimeOfDay.allCases,
                selectedID: config.timeOfDay.id,
                title: { $0.displayName },
                symbol: { $0.symbolName }
            ) { tapped in
                config.timeOfDay = tapped
                Haptics.tap()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 0))
        }
    }

    // MARK: - 色

    private var skyColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: config.skyColorHex) },
            set: { config.skyColorHex = $0.hexString }
        )
    }

    private var seaColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: config.seaColorHex) },
            set: { config.seaColorHex = $0.hexString }
        )
    }

    private var colorSection: some View {
        Section("色") {
            ColorPicker("空の色", selection: skyColorBinding, supportsOpacity: false)
            ColorPicker("海の色", selection: seaColorBinding, supportsOpacity: false)
            Button("時間帯の標準色に戻す") {
                config.skyColorHex = AppTheme.defaultSkyHex(for: config.timeOfDay)
                config.seaColorHex = AppTheme.defaultSeaHex(for: config.timeOfDay)
                Haptics.tap()
            }
            .font(.subheadline)
        }
    }

    // MARK: - 海と砂

    private var seaSection: some View {
        Section("海と砂") {
            Toggle("海を入れる", isOn: $config.hasSea)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("砂の量")
                    Spacer()
                    Text("\(Int(config.sandAmount * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $config.sandAmount, in: 0...1)
            }
        }
    }

    // MARK: - ラベル

    private var labelSection: some View {
        Section("ラベルの文") {
            TextField("例: 2026.7.13 江ノ島 — 波の音と、スイカの午後",
                      text: $config.labelText,
                      axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // MARK: - 演出

    private var effectSection: some View {
        Section("演出") {
            Picker("パーティクル", selection: $config.particle) {
                ForEach(ParticleKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Picker("環境音", selection: $config.soundscape) {
                ForEach(SoundscapeKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
        }
    }

    // MARK: - ミニチュア

    private var addableTypes: [SceneObjectType] {
        SceneObjectType.allCases.filter { $0 != .photoCard }
    }

    private var objectsSection: some View {
        Section {
            if config.objects.isEmpty {
                Text("ミニチュアがありません。下のメニューから追加できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($config.objects) { $object in
                SceneEditObjectRow(object: $object) {
                    removeObject(object.id)
                }
            }
            Menu {
                ForEach(addableTypes) { type in
                    Button(type.displayName) {
                        addObject(type)
                    }
                }
            } label: {
                Label("ミニチュアを追加", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("ミニチュア")
        } footer: {
            Text("行を開くと位置・回転・大きさを調整できます。フォトカードは移動のみです。")
        }
    }

    private func addObject(_ type: SceneObjectType) {
        let angle = Float.random(in: 0..<(2 * Float.pi))
        let radius = Float.random(in: 0.35...0.7)
        let y: Float
        switch type {
        case .cloud: y = 0.7
        case .fireworks: y = 0.78
        case .lanternString: y = 0.5
        default: y = 0
        }
        config.objects.append(SceneObject(
            type: type,
            position: SIMD3<Float>(radius * cosf(angle), y, radius * sinf(angle)),
            rotationY: 0,
            scale: 1
        ))
        Haptics.tap()
    }

    private func removeObject(_ id: UUID) {
        config.objects.removeAll { $0.id == id }
        Haptics.tap()
    }
}

// MARK: - ミニチュア編集行

fileprivate struct SceneEditObjectRow: View {
    @Binding var object: SceneObject
    let onDelete: () -> Void

    private var isPhotoCard: Bool {
        object.type == .photoCard
    }

    var body: some View {
        DisclosureGroup {
            sliderRow(title: "位置 左右", value: $object.position.x, range: -1...1)
            sliderRow(title: "位置 前後", value: $object.position.z, range: -1...1)
            if !isPhotoCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("回転")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(object.rotationY * 180 / Float.pi))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $object.rotationY, in: -Float.pi...Float.pi)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("大きさ")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "×%.2f", object.scale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $object.scale, in: 0.5...2)
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("このミニチュアを削除", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(object.type.displayName)
                if isPhotoCard {
                    Text("移動のみ")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
