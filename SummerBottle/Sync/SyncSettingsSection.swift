//
//  SyncSettingsSection.swift
//  SummerBottle
//
//  設定画面の Form に埋め込む同期セクション(契約書13章)。
//  状態に応じて 3 段階の UI を出す:
//    1. 未設定       → URL / anonキー入力 + 保存
//    2. 設定済み未ログイン → メール入力「コード送信」→ 6桁コード入力「ログイン」
//    3. ログイン済み  → 状態表示 + 今すぐ同期(同期中は ProgressView)+ ログアウト
//

import SwiftUI

struct SyncSettingsSection: View {
    @Environment(BottleStore.self) private var store

    @State private var urlText = ""
    @State private var keyText = ""
    @State private var emailText = ""
    @State private var codeText = ""
    @State private var isCodeSent = false
    @State private var isRequestingCode = false
    @State private var isVerifying = false
    @State private var isEditingConfig = false
    @State private var errorText: String?

    private var sync: SyncService { SyncService.shared }

    init() {}

    var body: some View {
        Section {
            if !sync.isConfigured || isEditingConfig {
                configRows
            } else if !sync.isSignedIn {
                signInRows
            } else {
                signedInRows
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("同期(Supabase)")
        } footer: {
            Text("設定しなくてもアプリはローカルだけで完全に動作します。同期を有効にすると、ボトルと写真・音声が自分のSupabaseプロジェクトへ保存されます。設定手順は docs/SUPABASE.md を参照してください。")
        }
    }

    // MARK: - 1. URL / anonキー設定

    @ViewBuilder
    private var configRows: some View {
        TextField("プロジェクトURL(https://xxxx.supabase.co)", text: $urlText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("anonキー(公開キー)", text: $keyText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.footnote.monospaced())

        Button {
            errorText = nil
            sync.configure(urlString: urlText, anonKey: keyText)
            isEditingConfig = false
            keyText = ""
            Haptics.tap()
        } label: {
            Label("保存", systemImage: "checkmark.circle.fill")
        }
        .disabled(
            urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        if isEditingConfig {
            Button("キャンセル", role: .cancel) {
                isEditingConfig = false
                errorText = nil
            }
        }
    }

    // MARK: - 2. メールOTPログイン

    @ViewBuilder
    private var signInRows: some View {
        LabeledContent("状態") {
            Text(sync.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }

        TextField("メールアドレス", text: $emailText)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        Button {
            requestCode()
        } label: {
            if isRequestingCode {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("送信中…")
                }
            } else {
                Label(isCodeSent ? "コードを再送信" : "コード送信", systemImage: "paperplane.fill")
            }
        }
        .disabled(!emailText.contains("@") || isRequestingCode || isVerifying)

        if isCodeSent {
            TextField("6桁の確認コード", text: $codeText)
                .keyboardType(.numberPad)
                .font(.body.monospacedDigit())

            Button {
                verifyCode()
            } label: {
                if isVerifying {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("確認中…")
                    }
                } else {
                    Label("ログイン", systemImage: "person.badge.key.fill")
                }
            }
            .disabled(codeText.trimmingCharacters(in: .whitespaces).count < 6 || isVerifying)
        }

        Button("URL・キーを設定し直す") {
            isEditingConfig = true
            errorText = nil
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - 3. ログイン済み

    @ViewBuilder
    private var signedInRows: some View {
        LabeledContent("状態") {
            Text(sync.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }

        if let email = UserDefaults.standard.string(forKey: SyncSettingsKeys.email), !email.isEmpty {
            LabeledContent("アカウント") {
                Text(email)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Button {
            errorText = nil
            Task {
                await sync.syncNow(store: store)
            }
        } label: {
            if sync.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("同期中…")
                }
            } else {
                Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(sync.isSyncing)

        Button("ログアウト", role: .destructive) {
            sync.signOut()
            isCodeSent = false
            codeText = ""
            errorText = nil
        }
        .disabled(sync.isSyncing)
    }

    // MARK: - アクション

    private func requestCode() {
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        isRequestingCode = true
        errorText = nil
        Task {
            do {
                try await sync.requestOTP(email: email)
                isCodeSent = true
                Haptics.tap()
            } catch {
                errorText = error.localizedDescription
            }
            isRequestingCode = false
        }
    }

    private func verifyCode() {
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !code.isEmpty else { return }
        isVerifying = true
        errorText = nil
        Task {
            do {
                try await sync.verifyOTP(email: email, code: code)
                isCodeSent = false
                codeText = ""
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
            }
            isVerifying = false
        }
    }
}
