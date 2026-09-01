//
//  AudioRecorderSheet.swift
//  SummerBottle
//
//  環境音の録音シート。最大15秒で自動停止し、レベルメーター(波形)を表示する。
//  停止後は試聴と「人の声が入っている」確認(仕様書10章)を経て
//  onComplete(url, duration, containsVoice) を呼ぶ。キャンセル可。
//

import AVFoundation
import SwiftUI

struct AudioRecorderSheet: View {

    init(onComplete: @escaping (_ url: URL, _ duration: TimeInterval, _ containsVoice: Bool) -> Void) {
        self.onComplete = onComplete
    }

    private let onComplete: (_ url: URL, _ duration: TimeInterval, _ containsVoice: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum RecorderPhase {
        case idle       // 録音前
        case recording  // 録音中
        case recorded   // 録音済み(試聴・確認)
    }

    @State private var phase: RecorderPhase = .idle
    @State private var recorder: AVAudioRecorder?
    @State private var meterTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var levels: [CGFloat] = []

    @State private var recordedURL: URL?
    @State private var recordedDuration: TimeInterval = 0
    @State private var containsVoice: Bool = false

    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewTask: Task<Void, Never>?
    @State private var isPreviewPlaying: Bool = false

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    private let maxDuration: TimeInterval = 15
    private let barCount = 40

    // MARK: - ボディ

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 8)
                switch phase {
                case .idle: idleSection
                case .recording: recordingSection
                case .recorded: recordedSection
                }
                Spacer(minLength: 8)
            }
            .padding(24)
            .navigationTitle("今日の音を録る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { cancelAndDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(phase == .recording)
        .alert("録音できません", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onDisappear { teardown() }
    }

    // MARK: - 録音前

    private var idleSection: some View {
        VStack(spacing: 24) {
            Text("波の音、セミの声、街のざわめき。\nこの瞬間の音を最大15秒だけ閉じ込めます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                startRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.coral)
                        .frame(width: 96, height: 96)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            Text("タップで録音をはじめる")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 録音中

    private var recordingSection: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text("録音中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            waveform
            Text(timeText)
                .font(.system(.title2, design: .monospaced))
            ProgressView(value: min(elapsed, maxDuration), total: maxDuration)
                .tint(AppTheme.coral)
            Button {
                finishRecording()
            } label: {
                ZStack {
                    Circle()
                        .stroke(AppTheme.coral, lineWidth: 3)
                        .frame(width: 84, height: 84)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.coral)
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.plain)
            Text("15秒で自動的に停止します")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(AppTheme.ocean)
                    .frame(width: 4, height: 8 + levelForBar(index) * 56)
            }
        }
        .frame(height: 72)
    }

    private var timeText: String {
        let seconds = Int(min(elapsed, maxDuration))
        return String(format: "0:%02d / 0:15", seconds)
    }

    private func levelForBar(_ index: Int) -> CGFloat {
        let deficit = barCount - levels.count
        if index < deficit { return 0.03 }
        return levels[index - deficit]
    }

    // MARK: - 録音済み

    private var recordedSection: some View {
        VStack(spacing: 20) {
            Label("録音できました(\(String(format: "%.1f", recordedDuration))秒)",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ocean)

            Button {
                togglePreview()
            } label: {
                Label(isPreviewPlaying ? "停止" : "試聴する",
                      systemImage: isPreviewPlaying ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ocean)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("人の声が入っている", isOn: $containsVoice)
                Text("会話や声が入っている場合はオンにしてください。書き出し・共有時の取り扱い確認に使われます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )

            Button {
                useRecording()
            } label: {
                Text("この音を使う")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.coral)

            Button("録り直す") { retake() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 録音制御

    private func startRecording() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            if granted {
                beginRecording()
            } else {
                alertMessage = "マイクへのアクセスが許可されていません。設定アプリの「プライバシーとセキュリティ > マイク」から許可してください。"
                showAlert = true
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            showRecordingFailure()
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("summer-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                showRecordingFailure()
                return
            }
            recorder = newRecorder
            recordedURL = url
            elapsed = 0
            levels = []
            containsVoice = false
            phase = .recording
            Haptics.medium()
            startMeterTask()
        } catch {
            showRecordingFailure()
        }
    }

    private func startMeterTask() {
        meterTask?.cancel()
        meterTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { break }
                tick()
            }
        }
    }

    private func tick() {
        guard phase == .recording, let recorder else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let power = recorder.averagePower(forChannel: 0) // -160...0 dB
        let clamped = max(-50.0, min(0.0, Double(power)))
        let level = max(0.05, CGFloat((clamped + 50.0) / 50.0))
        levels.append(level)
        if levels.count > barCount {
            levels.removeFirst(levels.count - barCount)
        }
        if elapsed >= maxDuration {
            finishRecording()
        }
    }

    private func finishRecording() {
        guard phase == .recording, let activeRecorder = recorder else { return }
        meterTask?.cancel()
        meterTask = nil
        let duration = min(activeRecorder.currentTime, maxDuration)
        activeRecorder.stop()
        recorder = nil
        recordedDuration = duration > 0 ? duration : min(elapsed, maxDuration)
        phase = .recorded
        Haptics.success()
    }

    private func showRecordingFailure() {
        recorder = nil
        phase = .idle
        alertMessage = "録音を開始できませんでした。マイクが使用できない環境(シミュレータなど)の可能性があります。"
        showAlert = true
    }

    // MARK: - 試聴

    private func togglePreview() {
        if isPreviewPlaying {
            stopPreview()
            return
        }
        guard let url = recordedURL else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            isPreviewPlaying = true
            startPreviewWatcher()
        } catch {
            alertMessage = "録音した音を再生できませんでした。"
            showAlert = true
        }
    }

    private func startPreviewWatcher() {
        previewTask?.cancel()
        previewTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { break }
                if previewPlayer?.isPlaying != true {
                    previewPlayer = nil
                    isPreviewPlaying = false
                    break
                }
            }
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewPlaying = false
    }

    // MARK: - 完了・キャンセル

    private func useRecording() {
        guard let url = recordedURL else { return }
        stopPreview()
        Haptics.success()
        onComplete(url, recordedDuration, containsVoice)
        dismiss()
    }

    private func retake() {
        stopPreview()
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
        recordedDuration = 0
        containsVoice = false
        elapsed = 0
        levels = []
        phase = .idle
    }

    private func cancelAndDismiss() {
        teardown()
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        dismiss()
    }

    /// 再生・録音・タイマーを止める(ファイルは消さない: onComplete後もURLは使われる)
    private func teardown() {
        meterTask?.cancel()
        meterTask = nil
        previewTask?.cancel()
        previewTask = nil
        recorder?.stop()
        recorder = nil
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewPlaying = false
    }
}
