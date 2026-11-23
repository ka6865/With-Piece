import Flutter
import ImageIO
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HeicEncoderPlugin") {
      HeicEncoderPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoExport") {
      let channel = FlutterMethodChannel(
        name: "kr.wooripiece/photo_export", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "save",
          let bytes = (call.arguments as? FlutterStandardTypedData)?.data
        else {
          result(FlutterError(code: "bad_args", message: nil, details: nil))
          return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else {
            result(FlutterError(code: "photo_permission", message: nil, details: nil))
            return
          }
          PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: bytes, options: nil)
          } completionHandler: { success, error in
            if success { result(nil) }
            else { result(FlutterError(code: "photo_save", message: error?.localizedDescription, details: nil)) }
          }
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScanCacheDirectory") {
      let channel = FlutterMethodChannel(
        name: "kr.wooripiece/scan_cache", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "directory" else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
          result(try ScanCacheDirectory.prepare(in: support).path)
        } catch {
          result(FlutterError(code: "scan_cache_directory", message: nil, details: nil))
        }
      }
    }
  }
}

enum ScanCacheDirectory {
  static func prepare(in support: URL) throws -> URL {
    var directory = support.appendingPathComponent("scan_snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // 사귄 날 이전을 포함한 스캔 집계도 백업에 들어가지 않아야 한다.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    return directory
  }
}

// 사진을 축소해 HEIC로 다시 쓴다(설계 8.1.1). 원본 속성을 복사하지 않으므로
// GPS와 기기 정보가 결과에 남지 않는다. 별도 파일로 두면 Xcode 프로젝트 파일을
// 손으로 고쳐야 해서 AppDelegate와 같은 파일에 둔다
final class HeicEncoderPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kr.wooripiece/heic", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HeicEncoderPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let source = (args["source"] as? FlutterStandardTypedData)?.data
    else {
      result(FlutterError(code: "bad_args", message: nil, details: nil))
      return
    }
    switch call.method {
    case "encode":
      // JPEG는 HEIC를 쓸 수 없는 기기의 폴백이다(설계 8.1.1)
      let type = (args["format"] as? String) == "jpeg" ? "public.jpeg" : "public.heic"
      guard let maxSide = args["maxSide"] as? Int, let quality = args["quality"] as? Int else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let encoded = Self.encode(source, maxSide: maxSide, quality: quality, type: type)
        DispatchQueue.main.async {
          if let encoded {
            result(FlutterStandardTypedData(bytes: encoded))
          } else {
            result(FlutterError(code: "unsupported", message: "HEIC 인코딩 실패", details: nil))
          }
        }
      }
    case "inspect":
      guard let image = CGImageSourceCreateWithData(source as CFData, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
      else {
        result(FlutterError(code: "bad_image", message: nil, details: nil))
        return
      }
      result([
        "width": props[kCGImagePropertyPixelWidth] as? Int ?? 0,
        "height": props[kCGImagePropertyPixelHeight] as? Int ?? 0,
        "hasGps": props[kCGImagePropertyGPSDictionary] != nil,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func encode(_ data: Data, maxSide: Int, quality: Int, type: String) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSide,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0, thumbnailOptions as CFDictionary)
    else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, type as CFString, 1, nil)
    else { return nil }
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: Double(quality) / 100
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
