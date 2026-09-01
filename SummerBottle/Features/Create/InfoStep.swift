//
//  InfoStep.swift
//  SummerBottle
//
//  作成フロー ステップ2: 基本情報の入力。
//  タイトル(必須)/日付/場所(現在地ボタン付き・任意)/一言/一緒にいた人/
//  思い出の種類チップ/天気・時間帯(自動 or 手動)/環境音の録音(AudioRecorderSheet)。
//

import CoreLocation
import SwiftUI

/// 作成フロー ステップ2: 基本情報の入力。
struct InfoStep: View {
    @Bindable var draft: BottleDraft
    let onBack: () -> Void
    let onNext: () -> Void

    init(draft: BottleDraft, onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.draft = draft
        self.onBack = onBack
        self.onNext = onNext
    }

    @State private var isFetchingLocation = false
    @State private var showRecorder = false

    private var isTitleValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                titleSection
                dateSection
                locationSection
                commentSection
                companionsSection
                memoryTypeSection
                weatherTimeSection
                audioSection
            }
            .scrollDismissesKeyboard(.interactively)
            CreateStepFooter(
                nextTitle: "解析へ進む",
                nextEnabled: isTitleValid,
                onBack: onBack,
                onNext: onNext
            )
        }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderSheet { url, duration, containsVoice in
                applyRecording(url: url, duration: duration, containsVoice: containsVoice)
            }
        }
    }

    // MARK: - セクション

    private var titleSection: some View {
        Section {
            TextField("例: 江ノ島で海びらき", text: $draft.title)
        } header: {
            Text("タイトル(必須)")
        } footer: {
            if !isTitleValid {
                Text("タイトルを入力すると次へ進めます。")
                    .foregroundStyle(AppTheme.coral)
            }
        }
    }

    private var dateSection: some View {
        Section("日付") {
            DatePicker("思い出の日付", selection: $draft.memoryDate, displayedComponents: .date)
        }
    }

    private var locationSection: some View {
        Section {
            TextField("例: 江ノ島", text: $draft.locationName)
            Button {
                fetchCurrentLocation()
            } label: {
                if isFetchingLocation {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("現在地を取得しています…")
                    }
                } else {
                    Label("現在地から入力", systemImage: "location.fill")
                }
            }
            .disabled(isFetchingLocation)
            if draft.latitude != nil, draft.longitude != nil {
                HStack {
                    Label("位置情報を一緒に記録します", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("削除", role: .destructive) {
                        draft.latitude = nil
                        draft.longitude = nil
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("場所")
        } footer: {
            Text("位置情報の利用は任意です。記録したくない場合は空欄のままで構いません。")
        }
    }

    private var commentSection: some View {
        Section("一言") {
            TextField("例: 波が高くて、スイカが甘かった", text: $draft.comment, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private var companionsSection: some View {
        Section {
            TextField("例: はるか、けんた", text: $draft.companionsText)
            if !draft.companions.isEmpty {
                Text(draft.companions.joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("一緒にいた人")
        } footer: {
            Text("読点やカンマで区切って複数入力できます。")
        }
    }

    private var memoryTypeSection: some View {
        Section {
            CreateChipRow(
                items: MemoryType.allCases,
                selectedID: draft.memoryType?.id,
                title: { $0.displayName },
                symbol: { $0.symbolName }
            ) { tapped in
                draft.memoryType = (draft.memoryType == tapped) ? nil : tapped
                Haptics.tap()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 0))
        } header: {
            Text("思い出の種類")
        } footer: {
            Text("もう一度タップすると選択を解除できます。")
        }
    }

    private var weatherTimeSection: some View {
        Section {
            Picker("天気", selection: $draft.weatherOverride) {
                Text("自動(晴れ)").tag(nil as WeatherKind?)
                ForEach(WeatherKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName)
                        .tag(kind as WeatherKind?)
                }
            }
            Picker("時間帯", selection: $draft.timeOverride) {
                Text("自動(写真から判定)").tag(nil as TimeOfDay?)
                ForEach(TimeOfDay.allCases) { time in
                    Label(time.displayName, systemImage: time.symbolName)
                        .tag(time as TimeOfDay?)
                }
            }
        } header: {
            Text("天気と時間帯")
        } footer: {
            Text("「自動」のままにすると、天気は晴れ、時間帯は写真の雰囲気から決まります。")
        }
    }

    private var audioSection: some View {
        Section {
            if draft.recordedAudioURL != nil {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.ocean)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("録音済み(\(String(format: "%.1f", draft.recordedDuration))秒)")
                        if draft.recordedContainsVoice {
                            Text("人の声を含む")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("録り直す") {
                        showRecorder = true
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        deleteRecording()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("録音を削除")
                }
            } else {
                Button {
                    showRecorder = true
                } label: {
                    Label("環境音を録音する", systemImage: "mic.fill")
                }
            }
        } header: {
            Text("環境音")
        } footer: {
            Text("波音やセミの声など、その日の音を最大15秒まで一緒に閉じ込められます(任意)。")
        }
    }

    // MARK: - 録音

    private func applyRecording(url: URL, duration: TimeInterval, containsVoice: Bool) {
        if let old = draft.recordedAudioURL, old != url {
            try? FileManager.default.removeItem(at: old)
        }
        draft.recordedAudioURL = url
        draft.recordedDuration = duration
        draft.recordedContainsVoice = containsVoice
    }

    private func deleteRecording() {
        if let url = draft.recordedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        draft.recordedAudioURL = nil
        draft.recordedDuration = 0
        draft.recordedContainsVoice = false
        Haptics.tap()
    }

    // MARK: - 現在地の取得(失敗はすべて無視する)

    private func fetchCurrentLocation() {
        guard !isFetchingLocation else { return }
        isFetchingLocation = true
        Task {
            let locationTask = Task { () throws -> CLLocation? in
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return location
                    }
                }
                return nil
            }
            // 許可待ちなどで返ってこない場合に備えたタイムアウト
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(12))
                locationTask.cancel()
            }

            var location: CLLocation?
            do {
                location = try await locationTask.value
            } catch {
                location = nil
            }
            timeoutTask.cancel()

            if let location {
                draft.latitude = location.coordinate.latitude
                draft.longitude = location.coordinate.longitude
                await reverseGeocode(location)
            }
            isFetchingLocation = false
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let geocoder = CLGeocoder()
        guard let placemark = (try? await geocoder.reverseGeocodeLocation(location))?.first else {
            return
        }
        let name = [placemark.locality, placemark.subLocality]
            .compactMap { $0 }
            .joined()
        if !name.isEmpty {
            draft.locationName = name
        } else if let fallback = placemark.name ?? placemark.administrativeArea {
            draft.locationName = fallback
        }
    }
}
