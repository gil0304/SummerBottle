//
//  ExportRenderer.swift
//  SummerBottle
//
//  静止画・ポスター・ポストカード・ループ動画のオフスクリーンレンダリング。
//  ARView(cameraMode: .nonAR) をほぼ不可視の状態で keyWindow の最背面に一時追加し、
//  BottleSceneController のシーンをスナップショットして各形式へ加工する。
//

import SwiftUI
import UIKit
import RealityKit
import AVFoundation
import CoreVideo
import CoreGraphics

@MainActor
final class ExportRenderer {

    init() {}

    // MARK: - 内部: オフスクリーンシーン一式

    private struct SceneRig {
        let arView: ARView
        /// 内容物をまとめて回すためのラッパー
        let spin: Entity
        let camera: PerspectiveCamera
        let bottleHeight: Float
    }

    /// 透過書き出しのキー色(マゼンタ)
    private static let chromaKey = UIColor(red: 1, green: 0, blue: 1, alpha: 1)

    // MARK: - 静止画

    /// 正方形・9:16・16:9・透過背景の静止画を書き出す。
    /// transparent のときはキー色背景でスナップショットし、ピクセル走査で透過化する。
    func renderStill(bottle: Bottle, photos: [UUID: CGImage], size: CGSize, transparent: Bool) async -> UIImage? {
        let background: UIColor = transparent
            ? Self.chromaKey
            : UIColor(hex: bottle.sceneConfig.skyColorHex)
        guard let shot = await snapshotScene(bottle: bottle, photos: photos, size: size, background: background) else {
            return nil
        }
        if transparent {
            return Self.removingChromaKey(from: shot)
        }
        return shot
    }

    // MARK: - ポスター

    /// 縦長ポスター(スナップショット+タイトル・日付・一言を ImageRenderer で合成)
    func renderPoster(bottle: Bottle, photos: [UUID: CGImage]) async -> UIImage? {
        guard let shot = await snapshotScene(
            bottle: bottle,
            photos: photos,
            size: CGSize(width: 900, height: 900),
            background: UIColor(hex: bottle.sceneConfig.skyColorHex)
        ) else { return nil }
        return Self.renderCanvas(
            ExportPosterCanvas(bottleImage: shot, bottle: bottle),
            size: CGSize(width: 1080, height: 1620)
        )
    }

    // MARK: - ポストカード

    /// ポストカード(表=ボトル、裏=日付・場所・一言+切手枠風の飾り)
    func renderPostcard(bottle: Bottle, photos: [UUID: CGImage]) async -> (front: UIImage, back: UIImage)? {
        guard let shot = await snapshotScene(
            bottle: bottle,
            photos: photos,
            size: CGSize(width: 820, height: 820),
            background: UIColor(hex: bottle.sceneConfig.skyColorHex)
        ) else { return nil }
        let cardSize = CGSize(width: 1470, height: 1050)
        guard
            let front = Self.renderCanvas(ExportPostcardFrontCanvas(bottleImage: shot, bottle: bottle), size: cardSize),
            let back = Self.renderCanvas(ExportPostcardBackCanvas(bottle: bottle), size: cardSize)
        else { return nil }
        return (front, back)
    }

    // MARK: - ループ動画

    /// ループ動画(30fps 1080x1920 H.264)。
    /// カメラが近づく → 内容がゆっくりY回転 → 後半にラベル・日付のオーバーレイ → 元へ戻る。
    /// フレーム毎に カメラ移動 → snapshot → pixel buffer append。
    func renderLoopVideo(
        bottle: Bottle,
        photos: [UUID: CGImage],
        duration: TimeInterval,
        progress: @escaping (Double) -> Void
    ) async -> URL? {
        let outputSize = CGSize(width: 1080, height: 1920)
        let fps = 30
        let totalFrames = max(Int(duration * Double(fps)), fps)

        let rig = makeRig(
            bottle: bottle,
            photos: photos,
            viewSize: outputSize,
            background: UIColor(hex: bottle.sceneConfig.skyColorHex)
        )
        attach(rig.arView)
        defer { detach(rig.arView) }
        // シーン構築(テクスチャ読み込み等)の安定待ち
        try? await Task.sleep(for: .milliseconds(450))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummerBottle_video_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { return nil }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
            ]
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        // ラベル・日付のオーバーレイ(1回だけ描画して毎フレーム合成)
        let overlay = Self.renderCanvas(ExportVideoOverlayCanvas(bottle: bottle), size: outputSize)?.cgImage

        var appendedFrames = 0
        for frame in 0..<totalFrames {
            let t = Double(frame) / Double(totalFrames)
            applyCameraPath(rig: rig, t: t)

            guard let shot = await snapshot(rig.arView), let shotCG = shot.cgImage else { continue }

            // 書き込み待ち(UIを固めないよう await でポーリング)
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }

            let alpha = Self.overlayAlpha(at: t)
            guard let buffer = Self.makePixelBuffer(
                image: shotCG,
                overlay: overlay,
                overlayAlpha: alpha,
                size: outputSize,
                pool: adaptor.pixelBufferPool
            ) else { continue }

            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            if adaptor.append(buffer, withPresentationTime: time) {
                appendedFrames += 1
            }
            progress(Double(frame + 1) / Double(totalFrames))
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard appendedFrames > 0, writer.status == .completed else { return nil }
        return outputURL
    }

    // MARK: - シーン構築

    private func makeRig(bottle: Bottle, photos: [UUID: CGImage], viewSize: CGSize, background: UIColor) -> SceneRig {
        let arView = ARView(
            frame: CGRect(origin: .zero, size: viewSize),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.environment.background = .color(background)
        arView.isUserInteractionEnabled = false

        let controller = BottleSceneController(config: bottle.sceneConfig, photos: photos)
        let spin = Entity()
        spin.addChild(controller.rootEntity)

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(spin)

        let height = max(controller.bottleHeight, 0.05)
        let camera = PerspectiveCamera()
        camera.position = SIMD3<Float>(0, height * 0.58, height * 1.6)
        camera.look(at: SIMD3<Float>(0, height * 0.44, 0), from: camera.position, relativeTo: nil)
        anchor.addChild(camera)

        arView.scene.addAnchor(anchor)
        return SceneRig(arView: arView, spin: spin, camera: camera, bottleHeight: height)
    }

    /// keyWindow の最背面へほぼ不可視の状態で一時追加する(snapshot にはビュー階層が必要なため)
    private func attach(_ view: UIView) {
        guard let window = Self.keyWindow() else { return }
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        window.insertSubview(view, at: 0)
        // 端末スケールに引きずられないよう 1x に固定(出力ピクセル数を frame と一致させる)
        view.contentScaleFactor = 1
    }

    private func detach(_ view: UIView) {
        view.removeFromSuperview()
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    // MARK: - スナップショット

    private func snapshotScene(bottle: Bottle, photos: [UUID: CGImage], size: CGSize, background: UIColor) async -> UIImage? {
        let rig = makeRig(bottle: bottle, photos: photos, viewSize: size, background: background)
        attach(rig.arView)
        defer { detach(rig.arView) }
        // シーン構築の安定待ち
        try? await Task.sleep(for: .milliseconds(400))
        return await snapshot(rig.arView)
    }

    private func snapshot(_ arView: ARView) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - カメラ軌道(動画用)

    /// t(0...1)に応じてカメラ距離と内容の回転を更新する。
    /// 序盤: ease-in-out で接近 / 中盤: 内容がゆっくり1回転 / 終盤: 元の距離へ戻る(ループが繋がる)。
    private func applyCameraPath(rig: SceneRig, t: Double) {
        let h = rig.bottleHeight
        let far: Float = h * 1.95
        let near: Float = h * 1.22
        let approach = Float(Self.smoothstep(0.0, 0.28, t))
        let retreat = Float(Self.smoothstep(0.8, 1.0, t))
        var distance = far + (near - far) * approach
        distance += (far - distance) * retreat
        rig.camera.position = SIMD3<Float>(0, h * 0.58, distance)
        rig.camera.look(at: SIMD3<Float>(0, h * 0.44, 0), from: rig.camera.position, relativeTo: nil)

        let spinT = Self.smoothstep(0.1, 0.92, t)
        rig.spin.transform.rotation = simd_quatf(
            angle: Float(spinT * 2.0 * Double.pi),
            axis: SIMD3<Float>(0, 1, 0)
        )
    }

    /// ラベル・日付オーバーレイの不透明度(後半にフェードイン→フェードアウト)
    nonisolated private static func overlayAlpha(at t: Double) -> CGFloat {
        let fadeIn = smoothstep(0.4, 0.5, t)
        let fadeOut = 1.0 - smoothstep(0.78, 0.88, t)
        return CGFloat(min(fadeIn, fadeOut))
    }

    nonisolated private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - 画像加工

    /// SwiftUI ビューを固定ピクセルサイズで UIImage 化する(scale=1)
    private static func renderCanvas<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// キー色(マゼンタ)のピクセルを走査して alpha 0 にする
    nonisolated private static func removingChromaKey(from image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let result: CGImage? = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

            let buffer = base.assumingMemoryBound(to: UInt8.self)
            var offset = 0
            for _ in 0..<(width * height) {
                let r = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let b = Int(buffer[offset + 2])
                // マゼンタ寄り(赤・青が強く緑が弱い)のピクセルを透過に
                if r > 150, b > 150, g < 110, abs(r - b) < 90 {
                    buffer[offset] = 0
                    buffer[offset + 1] = 0
                    buffer[offset + 2] = 0
                    buffer[offset + 3] = 0
                }
                offset += 4
            }
            return context.makeImage()
        }

        guard let result else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }

    /// スナップショットを(必要ならアスペクトフィルで)ピクセルバッファへ描画し、
    /// オーバーレイをアルファ付きで合成する
    nonisolated private static func makePixelBuffer(
        image: CGImage,
        overlay: CGImage?,
        overlayAlpha: CGFloat,
        size: CGSize,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        }
        if pixelBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32ARGB,
                attrs as CFDictionary,
                &pixelBuffer
            )
        }
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                  data: base,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              )
        else { return nil }

        let fullRect = CGRect(origin: .zero, size: size)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(fullRect)

        // アスペクトフィル(snapshot 解像度が frame と異なっても正しく収める)
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(image, in: drawRect)

        if let overlay, overlayAlpha > 0.01 {
            context.setAlpha(overlayAlpha)
            context.draw(overlay, in: fullRect)
            context.setAlpha(1)
        }
        return buffer
    }
}

// MARK: - 動画オーバーレイ(ラベル・日付)

fileprivate struct ExportVideoOverlayCanvas: View {
    let bottle: Bottle

    private var labelText: String {
        let label = bottle.sceneConfig.labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? bottle.title : label
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            VStack(spacing: 22) {
                Text(labelText)
                    .font(.system(size: 58, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(bottle.memoryDate.japaneseDateString)
                    .font(.system(size: 40, weight: .medium))
                    .opacity(0.92)
                if let location = bottle.locationName, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 32))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .padding(.horizontal, 70)
            .padding(.bottom, 180)
        }
    }
}

// MARK: - ポスター合成ビュー(1080x1620)

fileprivate struct ExportPosterCanvas: View {
    let bottleImage: UIImage
    let bottle: Bottle

    private var textColor: Color {
        bottle.timeOfDay == .morning ? AppTheme.nightNavy : .white
    }

    var body: some View {
        ZStack {
            AppTheme.skyGradient(for: bottle.timeOfDay)
            VStack(spacing: 0) {
                Spacer(minLength: 60)
                Image(uiImage: bottleImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 840, height: 840)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 30).fill(.white))
                    .rotationEffect(.degrees(-1.6))
                    .shadow(color: .black.opacity(0.28), radius: 26, y: 16)
                Spacer(minLength: 56)
                VStack(spacing: 24) {
                    Text(bottle.title)
                        .font(.system(size: 64, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(bottle.memoryDate.japaneseDateString)
                        .font(.system(size: 40, weight: .medium))
                        .opacity(0.9)
                    if let comment = bottle.comment, !comment.isEmpty {
                        Text("「\(comment)」")
                            .font(.system(size: 36))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .opacity(0.88)
                    }
                    if let location = bottle.locationName, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 30))
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(textColor)
                .shadow(color: .black.opacity(bottle.timeOfDay == .morning ? 0 : 0.3), radius: 8, y: 3)
                .padding(.horizontal, 80)
                Spacer(minLength: 50)
                Text("— Summer Bottle —")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.65))
                    .padding(.bottom, 44)
            }
        }
    }
}

// MARK: - ポストカード表(1470x1050)

fileprivate struct ExportPostcardFrontCanvas: View {
    let bottleImage: UIImage
    let bottle: Bottle

    private var textColor: Color {
        bottle.timeOfDay == .morning ? AppTheme.nightNavy : .white
    }

    var body: some View {
        ZStack {
            Color.white
            ZStack {
                AppTheme.skyGradient(for: bottle.timeOfDay)
                HStack(spacing: 48) {
                    Image(uiImage: bottleImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 640, height: 640)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 26).fill(.white))
                        .rotationEffect(.degrees(1.4))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
                    VStack(alignment: .leading, spacing: 26) {
                        Text("SUMMER MEMORY")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(9)
                            .opacity(0.7)
                        Text(bottle.title)
                            .font(.system(size: 54, weight: .bold))
                            .lineLimit(3)
                        Text(bottle.memoryDate.japaneseDateString)
                            .font(.system(size: 34, weight: .medium))
                            .opacity(0.9)
                        if let location = bottle.locationName, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 28))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(textColor)
                    .shadow(color: .black.opacity(bottle.timeOfDay == .morning ? 0 : 0.3), radius: 8, y: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 64)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(30)
        }
    }
}

// MARK: - ポストカード裏(1470x1050)

fileprivate struct ExportPostcardBackCanvas: View {
    let bottle: Bottle

    private let paper = Color(hex: "#FFFDF4")
    private let line = Color(hex: "#C9BC9C")
    private let ink = Color(hex: "#4A4234")

    private var locationText: String {
        if let location = bottle.locationName, !location.isEmpty { return location }
        return "—"
    }

    var body: some View {
        ZStack {
            paper
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(line, lineWidth: 3)
                .padding(28)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text("POST CARD")
                        .font(.system(size: 42, weight: .semibold, design: .serif))
                        .tracking(14)
                        .foregroundStyle(ink.opacity(0.75))
                        .padding(.top, 16)
                    Spacer()
                    stampBox
                }
                .padding(.horizontal, 72)
                .padding(.top, 60)

                HStack(alignment: .top, spacing: 0) {
                    // 左半分: 一言・一緒にいた人
                    VStack(alignment: .leading, spacing: 30) {
                        if let comment = bottle.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.system(size: 34, design: .serif))
                                .lineSpacing(16)
                                .foregroundStyle(ink)
                        } else {
                            Text("あの夏の一日を、瓶に詰めて。")
                                .font(.system(size: 34, design: .serif))
                                .lineSpacing(16)
                                .foregroundStyle(ink.opacity(0.8))
                        }
                        if !bottle.companions.isEmpty {
                            Text("と、" + bottle.companions.joined(separator: "、"))
                                .font(.system(size: 28, design: .serif))
                                .foregroundStyle(ink.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 40)

                    Rectangle()
                        .fill(line)
                        .frame(width: 3)

                    // 右半分: 宛名風(日付・場所・タイトル)
                    VStack(alignment: .leading, spacing: 40) {
                        addressLine(caption: "日付", value: bottle.memoryDate.japaneseDateString)
                        addressLine(caption: "場所", value: locationText)
                        addressLine(caption: "タイトル", value: bottle.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, 40)
                }
                .padding(.horizontal, 72)
                .padding(.top, 52)

                Text("Summer Bottle")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(ink.opacity(0.45))
                    .padding(.bottom, 50)
            }
        }
    }

    /// 切手枠風の飾り
    private var stampBox: some View {
        VStack(spacing: 10) {
            Image(systemName: "water.waves")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.ocean)
            Text(bottle.memoryDate.shortDateString)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ink.opacity(0.7))
        }
        .frame(width: 168, height: 208)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                .foregroundStyle(line)
        )
    }

    private func addressLine(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ink.opacity(0.55))
            Text(value)
                .font(.system(size: 32, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
            Rectangle()
                .fill(line)
                .frame(height: 2)
        }
    }
}
