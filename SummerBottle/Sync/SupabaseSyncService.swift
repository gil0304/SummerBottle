//
//  SupabaseSyncService.swift
//  SummerBottle
//
//  Supabase(GoTrue / PostgREST / Storage)を URLSession で直接叩く同期レイヤー。
//  外部SDKは使わない。未設定ならすべて何もしない(アプリはローカルのみで完全動作)。
//
//  - 設定(URL / anonキー)は UserDefaults
//  - access / refresh トークンは Keychain(kSecClassGenericPassword)
//  - 同期方針: updatedAt 比較の双方向同期(新しい方が勝つ)
//  - bottles 行は仕様書17章のカラムを冗長に埋めつつ、payload 列(jsonb)に
//    Bottle 全体をエンコードして保存する(復元はこの payload を正とする)
//  - 写真・音声は Storage バケット bottle-media の <user_id>/<bottle_id>/<fileName>
//

import Foundation
import Observation
import Security

// MARK: - UserDefaults キー(SyncSettingsSection と共有するため internal)

enum SyncSettingsKeys {
    static let supabaseURL = "SyncService.supabaseURL"
    static let anonKey = "SyncService.anonKey"
    static let userID = "SyncService.userID"
    static let email = "SyncService.email"
}

// MARK: - 同期サービス(契約書13章)

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    // MARK: 公開状態

    var isConfigured: Bool {
        !supabaseURLString.isEmpty && !anonKey.isEmpty
    }

    private(set) var isSignedIn: Bool = false
    private(set) var isSyncing: Bool = false
    private(set) var statusText: String = ""

    // MARK: 内部状態

    private var supabaseURLString: String
    private var anonKey: String
    private var userID: String?
    private var accessToken: String?
    private var refreshToken: String?

    /// updatedAt 比較の許容差(ISO8601丸めで秒未満が落ちるため)
    private let conflictTolerance: TimeInterval = 1.5

    private init() {
        let defaults = UserDefaults.standard
        supabaseURLString = defaults.string(forKey: SyncSettingsKeys.supabaseURL) ?? ""
        anonKey = defaults.string(forKey: SyncSettingsKeys.anonKey) ?? ""
        userID = defaults.string(forKey: SyncSettingsKeys.userID)
        accessToken = SyncKeychain.string(for: SyncKeychain.accessTokenAccount)
        refreshToken = SyncKeychain.string(for: SyncKeychain.refreshTokenAccount)
        isSignedIn = !supabaseURLString.isEmpty && !anonKey.isEmpty
            && accessToken != nil && userID != nil
        if isSignedIn {
            let email = defaults.string(forKey: SyncSettingsKeys.email) ?? ""
            statusText = email.isEmpty ? "ログイン済み" : "ログイン済み(\(email))"
        } else if !supabaseURLString.isEmpty && !anonKey.isEmpty {
            statusText = "未ログイン"
        } else {
            statusText = "未設定(ローカルのみで動作中)"
        }
    }

    // MARK: - 設定

    func configure(urlString: String, anonKey: String) {
        var url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        let key = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = (url != supabaseURLString) || (key != self.anonKey)

        supabaseURLString = url
        self.anonKey = key
        let defaults = UserDefaults.standard
        defaults.set(url, forKey: SyncSettingsKeys.supabaseURL)
        defaults.set(key, forKey: SyncSettingsKeys.anonKey)

        // 接続先が変わったら古いセッションは無効
        if changed && isSignedIn {
            signOut()
        }
        if !isConfigured {
            statusText = "未設定(ローカルのみで動作中)"
        } else if !isSignedIn {
            statusText = "設定を保存しました。メールアドレスでログインしてください"
        }
    }

    // MARK: - 認証(メールOTP)

    /// 6桁の確認コードをメールへ送る
    func requestOTP(email: String) async throws {
        guard isConfigured else { throw SyncServiceError.notConfigured }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = ["email": trimmed, "create_user": true]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await send(
            path: "/auth/v1/otp",
            method: "POST",
            body: body,
            contentType: "application/json",
            authorized: false
        )
        statusText = "確認コードを \(trimmed) に送信しました"
    }

    /// メールで受け取った6桁コードでログインする
    func verifyOTP(email: String, code: String) async throws {
        guard isConfigured else { throw SyncServiceError.notConfigured }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "type": "email",
            "email": trimmedEmail,
            "token": trimmedCode,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await send(
            path: "/auth/v1/verify",
            method: "POST",
            body: body,
            contentType: "application/json",
            authorized: false
        )
        let session = try JSONDecoder().decode(SyncAuthSession.self, from: data)
        guard let user = session.user else { throw SyncServiceError.missingUser }

        storeSession(session)
        userID = user.id
        let defaults = UserDefaults.standard
        defaults.set(user.id, forKey: SyncSettingsKeys.userID)
        defaults.set(user.email ?? trimmedEmail, forKey: SyncSettingsKeys.email)
        isSignedIn = true
        statusText = "ログインしました(\(user.email ?? trimmedEmail))"
    }

    func signOut() {
        SyncKeychain.delete(SyncKeychain.accessTokenAccount)
        SyncKeychain.delete(SyncKeychain.refreshTokenAccount)
        accessToken = nil
        refreshToken = nil
        userID = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SyncSettingsKeys.userID)
        defaults.removeObject(forKey: SyncSettingsKeys.email)
        isSignedIn = false
        statusText = "ログアウトしました"
    }

    // MARK: - 同期本体

    /// 双方向同期。未設定/未ログインなら即 return する。
    func syncNow(store: BottleStore) async {
        guard isConfigured, isSignedIn,
              let userIDString = userID,
              let userUUID = UUID(uuidString: userIDString)
        else { return }
        guard !isSyncing else { return }

        isSyncing = true
        statusText = "同期中…"
        defer { isSyncing = false }

        var pulledCount = 0
        var pushedCount = 0
        var mediaFailures = 0

        do {
            // --- Pull: 自分の行だけが返る(RLS) ---
            let (data, _) = try await send(
                path: "/rest/v1/bottles",
                query: [URLQueryItem(name: "select", value: "*")],
                method: "GET"
            )
            let rows = try Self.makeRowDecoder()
                .decode([SyncFailableRow].self, from: data)
                .compactMap { $0.row }

            var remoteBottles: [UUID: Bottle] = [:]
            for row in rows {
                if let bottle = row.toBottle() { remoteBottles[bottle.id] = bottle }
            }

            let localBottles = store.bottles
            var localByID: [UUID: Bottle] = [:]
            for bottle in localBottles { localByID[bottle.id] = bottle }

            var toPush: [Bottle] = []

            // リモート各行: updatedAt 比較で新しい方を採用
            for (id, remote) in remoteBottles {
                if let local = localByID[id] {
                    if remote.updatedAt.timeIntervalSince(local.updatedAt) > conflictTolerance {
                        store.upsertFromRemote(remote)
                        pulledCount += 1
                        mediaFailures += await downloadMissingMedia(
                            for: remote, userIDString: userIDString, store: store)
                    } else if local.updatedAt.timeIntervalSince(remote.updatedAt) > conflictTolerance {
                        toPush.append(local)
                    } else {
                        // 同一とみなす。足りないメディアだけ補完する
                        mediaFailures += await downloadMissingMedia(
                            for: local, userIDString: userIDString, store: store)
                    }
                } else {
                    store.upsertFromRemote(remote)
                    pulledCount += 1
                    mediaFailures += await downloadMissingMedia(
                        for: remote, userIDString: userIDString, store: store)
                }
            }

            // ローカルにしか無いものは push
            for bottle in localBottles where remoteBottles[bottle.id] == nil {
                toPush.append(bottle)
            }

            if !toPush.isEmpty {
                mediaFailures += try await pushBottles(
                    toPush, userUUID: userUUID, userIDString: userIDString, store: store)
                pushedCount = toPush.count
            }

            if mediaFailures > 0 {
                statusText = "同期完了(受信 \(pulledCount)件 / 送信 \(pushedCount)件)。メディア\(mediaFailures)件の転送に失敗しました"
            } else {
                statusText = "同期完了(受信 \(pulledCount)件 / 送信 \(pushedCount)件)"
            }
        } catch {
            statusText = "同期に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Push(行 + メディア)

    /// 行を upsert し、続けてメディアをアップロードする。戻り値はメディア転送の失敗数。
    private func pushBottles(
        _ bottles: [Bottle],
        userUUID: UUID,
        userIDString: String,
        store: BottleStore
    ) async throws -> Int {
        guard !bottles.isEmpty else { return 0 }
        let rows = bottles.map { SyncBottleRow(bottle: $0, userID: userUUID) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(rows)
        _ = try await send(
            path: "/rest/v1/bottles",
            method: "POST",
            body: body,
            contentType: "application/json",
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
        var failures = 0
        for bottle in bottles {
            failures += await uploadMedia(for: bottle, userIDString: userIDString, store: store)
        }
        return failures
    }

    /// ボトルの写真・音声を Storage へアップロードする(存在時は上書き)。戻り値は失敗数。
    private func uploadMedia(
        for bottle: Bottle,
        userIDString: String,
        store: BottleStore
    ) async -> Int {
        var failures = 0
        for photo in bottle.photos {
            guard let data = store.photoData(bottleID: bottle.id, fileName: photo.fileName) else { continue }
            do {
                _ = try await send(
                    path: storagePath(userIDString: userIDString, bottleID: bottle.id, fileName: photo.fileName),
                    method: "POST",
                    body: data,
                    contentType: Self.contentType(forFileName: photo.fileName),
                    extraHeaders: ["x-upsert": "true"]
                )
            } catch {
                failures += 1
            }
        }
        if let fileName = bottle.audio?.fileName {
            let url = store.mediaDirectory(for: bottle.id).appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url) {
                do {
                    _ = try await send(
                        path: storagePath(userIDString: userIDString, bottleID: bottle.id, fileName: fileName),
                        method: "POST",
                        body: data,
                        contentType: Self.contentType(forFileName: fileName),
                        extraHeaders: ["x-upsert": "true"]
                    )
                } catch {
                    failures += 1
                }
            }
        }
        return failures
    }

    // MARK: - Pull(メディア)

    /// ローカルに無いメディアファイルを Storage から取得して保存する。戻り値は失敗数。
    private func downloadMissingMedia(
        for bottle: Bottle,
        userIDString: String,
        store: BottleStore
    ) async -> Int {
        var failures = 0
        let fileManager = FileManager.default
        for photo in bottle.photos {
            let destination = store.photoURL(bottleID: bottle.id, fileName: photo.fileName)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                let (data, _) = try await send(
                    path: storagePath(userIDString: userIDString, bottleID: bottle.id, fileName: photo.fileName),
                    method: "GET"
                )
                try data.write(to: destination, options: .atomic)
            } catch {
                failures += 1
            }
        }
        if let fileName = bottle.audio?.fileName {
            let destination = store.mediaDirectory(for: bottle.id).appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: destination.path) {
                do {
                    let (data, _) = try await send(
                        path: storagePath(userIDString: userIDString, bottleID: bottle.id, fileName: fileName),
                        method: "GET"
                    )
                    try data.write(to: destination, options: .atomic)
                } catch {
                    failures += 1
                }
            }
        }
        return failures
    }

    private func storagePath(userIDString: String, bottleID: UUID, fileName: String) -> String {
        "/storage/v1/object/bottle-media/\(userIDString)/\(bottleID.uuidString)/\(fileName)"
    }

    // MARK: - HTTP 基盤

    /// リクエストを送る。authorized の場合 401 なら refresh を試して1回だけ再送する。
    private func send(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(
            path: path, query: query, method: method, body: body,
            contentType: contentType, extraHeaders: extraHeaders, authorized: authorized)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncServiceError.http(0, "不正な応答")
        }

        if http.statusCode == 401 && authorized {
            try await refreshSession()
            var retry = request
            retry.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw SyncServiceError.http(0, "不正な応答")
            }
            guard (200..<300).contains(retryHTTP.statusCode) else {
                throw SyncServiceError.http(retryHTTP.statusCode, Self.bodySnippet(retryData))
            }
            return (retryData, retryHTTP)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SyncServiceError.http(http.statusCode, Self.bodySnippet(data))
        }
        return (data, http)
    }

    private func makeRequest(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Data?,
        contentType: String?,
        extraHeaders: [String: String],
        authorized: Bool
    ) throws -> URLRequest {
        guard isConfigured else { throw SyncServiceError.notConfigured }
        guard var components = URLComponents(string: supabaseURLString + path) else {
            throw SyncServiceError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SyncServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let bearer = (authorized ? accessToken : nil) ?? anonKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        return request
    }

    /// refresh_token でセッションを更新する。失敗したらセッションを破棄する。
    private func refreshSession() async throws {
        guard let refreshToken, !refreshToken.isEmpty else {
            clearSession()
            throw SyncServiceError.sessionExpired
        }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let request = try makeRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: body,
            contentType: "application/json",
            extraHeaders: [:],
            authorized: false
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            clearSession()
            throw SyncServiceError.sessionExpired
        }
        let session = try JSONDecoder().decode(SyncAuthSession.self, from: data)
        storeSession(session)
        if let user = session.user {
            userID = user.id
            UserDefaults.standard.set(user.id, forKey: SyncSettingsKeys.userID)
        }
        isSignedIn = true
    }

    private func storeSession(_ session: SyncAuthSession) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken ?? refreshToken
        SyncKeychain.set(session.accessToken, for: SyncKeychain.accessTokenAccount)
        if let refresh = session.refreshToken {
            SyncKeychain.set(refresh, for: SyncKeychain.refreshTokenAccount)
        }
    }

    private func clearSession() {
        SyncKeychain.delete(SyncKeychain.accessTokenAccount)
        SyncKeychain.delete(SyncKeychain.refreshTokenAccount)
        accessToken = nil
        refreshToken = nil
        isSignedIn = false
        statusText = "セッションの有効期限が切れました。もう一度ログインしてください"
    }

    // MARK: - ヘルパー

    private nonisolated static func bodySnippet(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.prefix(200))
    }

    private nonisolated static func contentType(forFileName fileName: String) -> String {
        let lowered = fileName.lowercased()
        if lowered.hasSuffix(".jpg") || lowered.hasSuffix(".jpeg") { return "image/jpeg" }
        if lowered.hasSuffix(".png") { return "image/png" }
        if lowered.hasSuffix(".heic") { return "image/heic" }
        if lowered.hasSuffix(".m4a") { return "audio/mp4" }
        if lowered.hasSuffix(".wav") { return "audio/wav" }
        if lowered.hasSuffix(".mp3") { return "audio/mpeg" }
        return "application/octet-stream"
    }

    /// PostgREST の応答用デコーダ。小数秒あり/なし両方の ISO8601 を受け付ける。
    private nonisolated static func makeRowDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = SyncISO8601.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "日付形式を解釈できません: \(string)")
        }
        return decoder
    }
}

// MARK: - ISO8601 パース(小数秒あり/なし)

private enum SyncISO8601 {
    nonisolated static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - エラー

private enum SyncServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case sessionExpired
    case missingUser
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "SupabaseのURLとanonキーが設定されていません"
        case .invalidURL:
            "SupabaseのURLが不正です"
        case .sessionExpired:
            "セッションの有効期限が切れました。もう一度ログインしてください"
        case .missingUser:
            "ユーザー情報を取得できませんでした"
        case .http(let code, let message):
            message.isEmpty ? "サーバーエラー(\(code))" : "サーバーエラー(\(code)): \(message)"
        }
    }
}

// MARK: - 認証応答

private struct SyncAuthUser: Decodable {
    var id: String
    var email: String?
}

private struct SyncAuthSession: Decodable {
    var accessToken: String
    var refreshToken: String?
    var user: SyncAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

// MARK: - bottles 行

/// public.bottles の1行。仕様書17章のカラムを冗長に埋めつつ、
/// payload に Bottle 全体を入れる(復元はこちらを正とする)。
private struct SyncBottleRow: Codable {
    var id: UUID
    var userID: UUID?
    var title: String?
    var memoryDate: Date?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var memoryType: String?
    var comment: String?
    var companions: [String]?
    var isFavorite: Bool?
    var sceneConfig: SceneConfig?
    var payload: Bottle?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, latitude, longitude, comment, companions, payload
        case userID = "user_id"
        case memoryDate = "memory_date"
        case locationName = "location_name"
        case memoryType = "memory_type"
        case isFavorite = "is_favorite"
        case sceneConfig = "scene_config"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(bottle: Bottle, userID: UUID) {
        self.id = bottle.id
        self.userID = userID
        self.title = bottle.title
        self.memoryDate = bottle.memoryDate
        self.locationName = bottle.locationName
        self.latitude = bottle.latitude
        self.longitude = bottle.longitude
        self.memoryType = bottle.memoryType?.rawValue
        self.comment = bottle.comment
        self.companions = bottle.companions
        self.isFavorite = bottle.isFavorite
        self.sceneConfig = bottle.sceneConfig
        self.payload = bottle
        self.createdAt = bottle.createdAt
        self.updatedAt = bottle.updatedAt
    }

    /// payload があればそれを、無ければ列から可能な範囲で復元する
    func toBottle() -> Bottle? {
        if let payload { return payload }
        var bottle = Bottle(
            id: id,
            title: title ?? "無題のボトル",
            memoryDate: memoryDate ?? createdAt ?? Date()
        )
        bottle.locationName = locationName
        bottle.latitude = latitude
        bottle.longitude = longitude
        bottle.memoryType = memoryType.flatMap(MemoryType.init(rawValue:))
        bottle.comment = comment
        bottle.companions = companions ?? []
        bottle.isFavorite = isFavorite ?? false
        bottle.sceneConfig = sceneConfig ?? SceneConfig()
        bottle.createdAt = createdAt ?? Date()
        bottle.updatedAt = updatedAt ?? .distantPast
        return bottle
    }
}

/// 1行のデコード失敗で全体を落とさないためのラッパー
private struct SyncFailableRow: Decodable {
    let row: SyncBottleRow?

    init(from decoder: Decoder) throws {
        row = try? SyncBottleRow(from: decoder)
    }
}

// MARK: - Keychain(Security framework 直)

private enum SyncKeychain {
    static let service = "com.summerbottle.sync"
    static let accessTokenAccount = "supabase.access_token"
    static let refreshTokenAccount = "supabase.refresh_token"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
