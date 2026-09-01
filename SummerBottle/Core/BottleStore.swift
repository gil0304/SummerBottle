//
//  BottleStore.swift
//  SummerBottle
//
//  ローカル永続化ストア。ボトルのJSON保存と写真・音声ファイルの管理を行う。
//  保存済みボトルはオフラインでも閲覧できる(非機能要件)。
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
@Observable
final class BottleStore {
    private(set) var bottles: [Bottle] = []

    /// 同期レイヤーが変更検知に使う: ローカルで更新された最終時刻
    private(set) var lastLocalChange: Date = .distantPast

    private let fileManager = FileManager.default

    private var baseDirectory: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SummerBottle", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bottlesFileURL: URL {
        baseDirectory.appendingPathComponent("bottles.json")
    }

    init() {
        load()
    }

    // MARK: - 読み書き

    private func load() {
        guard let data = try? Data(contentsOf: bottlesFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Bottle].self, from: data) {
            bottles = loaded.sorted { $0.memoryDate > $1.memoryDate }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bottles) {
            try? data.write(to: bottlesFileURL, options: .atomic)
        }
        lastLocalChange = Date()
    }

    // MARK: - CRUD

    func bottle(id: Bottle.ID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    /// 新規ボトルを追加する。photoDatas は BottlePhoto.id → 縮小済みJPEGデータ。
    /// audioSourceURL があればメディアディレクトリへコピーする。
    func add(_ bottle: Bottle, photoDatas: [UUID: Data], audioSourceURL: URL? = nil) {
        var bottle = bottle
        let dir = mediaDirectory(for: bottle.id)
        for photo in bottle.photos {
            guard let data = photoDatas[photo.id] else { continue }
            try? data.write(to: dir.appendingPathComponent(photo.fileName), options: .atomic)
        }
        if let source = audioSourceURL, let fileName = bottle.audio?.fileName {
            let dest = dir.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: dest)
            try? fileManager.copyItem(at: source, to: dest)
        }
        bottle.updatedAt = Date()
        bottles.append(bottle)
        bottles.sort { $0.memoryDate > $1.memoryDate }
        persist()
    }

    func update(_ bottle: Bottle) {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var bottle = bottle
        bottle.updatedAt = Date()
        bottles[index] = bottle
        bottles.sort { $0.memoryDate > $1.memoryDate }
        persist()
    }

    func delete(_ id: Bottle.ID) {
        bottles.removeAll { $0.id == id }
        try? fileManager.removeItem(at: mediaDirectory(for: id))
        persist()
    }

    func toggleFavorite(_ id: Bottle.ID) {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else { return }
        bottles[index].isFavorite.toggle()
        bottles[index].updatedAt = Date()
        persist()
    }

    /// 同期レイヤーがリモートから取り込むときに使う(ソート・保存のみ、updatedAtは変更しない)
    func replaceAll(with newBottles: [Bottle]) {
        bottles = newBottles.sorted { $0.memoryDate > $1.memoryDate }
        persist()
    }

    /// 同期レイヤー用: リモート由来のボトルを挿入/上書きする
    func upsertFromRemote(_ bottle: Bottle) {
        if let index = bottles.firstIndex(where: { $0.id == bottle.id }) {
            bottles[index] = bottle
        } else {
            bottles.append(bottle)
        }
        bottles.sort { $0.memoryDate > $1.memoryDate }
        persist()
    }

    // MARK: - メディアファイル

    /// ボトルごとのメディアディレクトリ(なければ作成)
    func mediaDirectory(for bottleID: Bottle.ID) -> URL {
        let dir = baseDirectory
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(bottleID.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func photoURL(bottleID: Bottle.ID, fileName: String) -> URL {
        mediaDirectory(for: bottleID).appendingPathComponent(fileName)
    }

    func audioURL(for bottle: Bottle) -> URL? {
        guard let fileName = bottle.audio?.fileName else { return nil }
        return mediaDirectory(for: bottle.id).appendingPathComponent(fileName)
    }

    func photoData(bottleID: Bottle.ID, fileName: String) -> Data? {
        try? Data(contentsOf: photoURL(bottleID: bottleID, fileName: fileName))
    }

    /// 3Dシーン用: ボトルの全写真を BottlePhoto.id → CGImage で返す(最大辺 maxPixel に縮小)
    func photoCGImages(for bottle: Bottle, maxPixel: CGFloat = 1024) -> [UUID: CGImage] {
        var result: [UUID: CGImage] = [:]
        for photo in bottle.photos {
            let url = photoURL(bottleID: bottle.id, fileName: photo.fileName)
            if let image = ImageUtil.cgImage(contentsOf: url, maxPixel: maxPixel) {
                result[photo.id] = image
            }
        }
        return result
    }
}
