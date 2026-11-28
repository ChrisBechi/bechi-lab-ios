import Flutter
import UIKit
import AVFAudio

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioChannel: FlutterMethodChannel?
  private var audioLeases = Set<String>()
  #if targetEnvironment(simulator)
  private var testChannel: FlutterMethodChannel?
  #endif
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BechiCatalogTabs") {
      CatalogTabs.register(with: registrar)
    }
    #if targetEnvironment(simulator)
    // Runtime-only simulator identity. No QA token or test channel is compiled
    // into device builds; Dart's environment map is empty on this iOS runner.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BechiSimulatorDiagnostics") {
      let channel = FlutterMethodChannel(name: "app.bechiflix.native/test", binaryMessenger: registrar.messenger())
      testChannel = channel
      channel.setMethodCallHandler { call, result in
        if call.method == "catalogTabs" {
          let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
          var queue = window?.rootViewController.map { [$0] } ?? []
          while let controller = queue.popLast() {
            if let tabs = controller as? UITabBarController, tabs.tabBar.window != nil {
              result(["index": tabs.selectedIndex, "labels": tabs.tabBar.items?.compactMap { $0.title } ?? [],
                      "height": tabs.tabBar.bounds.height])
              return
            }
            queue.append(contentsOf: controller.children)
          }
          result(nil)
          return
        }
        guard call.method == "context" else { result(FlutterMethodNotImplemented); return }
        result(["simulator": true, "qa_session": ProcessInfo.processInfo.environment["BECHI_QA_TOKEN"] ?? ""])
      }
    }
    #endif
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BechiAudioSession") {
      let channel = FlutterMethodChannel(name: "app.bechiflix.native/audio", binaryMessenger: registrar.messenger())
      audioChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self, let args = call.arguments as? [String: Any],
              let lease = args["lease"] as? String, UUID(uuidString: lease) != nil else {
          result(FlutterError(code: "AUDIO_INPUT", message: "Invalid audio session", details: nil)); return
        }
        let session = AVAudioSession.sharedInstance()
        do {
          if call.method == "activate" {
            if self.audioLeases.isEmpty { try session.setCategory(.playback, mode: .moviePlayback) }
            try session.setActive(true)
            self.audioLeases.insert(lease)
            result(["sample_rate": session.sampleRate, "output_channels": session.outputNumberOfChannels])
          } else if call.method == "release" {
            if self.audioLeases.remove(lease) != nil && self.audioLeases.isEmpty {
              try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            result(nil)
          } else { result(FlutterMethodNotImplemented) }
        } catch {
          result(FlutterError(code: "AUDIO_SESSION", message: "Não foi possível ativar a saída de áudio.", details: (error as NSError).code))
        }
      }
    }
    if #available(iOS 14.0, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BechiHostedSource") {
      HostedSource.register(with: registrar)
    }
  }
}
