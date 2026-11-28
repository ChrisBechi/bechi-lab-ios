import Flutter
import UIKit

final class CatalogTabs {
  static let viewType = "app.bechiflix.native/catalog-tabs"

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let availability = FlutterMethodChannel(name: viewType, binaryMessenger: messenger)
    if #available(iOS 26.0, *) {
      registrar.register(CatalogTabFactory(messenger), withId: viewType)
    }
    availability.setMethodCallHandler { call, result in
      guard call.method == "available" else { result(FlutterMethodNotImplemented); return }
      if #available(iOS 26.0, *) { result(true) } else { result(false) }
    }
  }
}

@available(iOS 26.0, *)
private final class CatalogTabFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments args: Any?) -> FlutterPlatformView {
    CatalogTabView(frame: frame, id: id, args: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

// UIKit owns gesture tracking, accessibility, material and selection animation.
// Flutter keeps the five catalog pages in its existing navigator.
@available(iOS 26.0, *)
private final class CatalogTabHost: UIView {
  let tabs = UITabBarController()

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if tabs.parent != nil {
        tabs.willMove(toParent: nil)
        tabs.view.removeFromSuperview()
        tabs.removeFromParent()
      }
      return
    }
    var owner: UIResponder? = next
    while let responder = owner, !(responder is UIViewController) { owner = responder.next }
    guard let parent = owner as? UIViewController, tabs.parent == nil else { return }
    parent.addChild(tabs)
    tabs.view.frame = bounds
    tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tabs.view.backgroundColor = .clear
    addSubview(tabs.view)
    tabs.didMove(toParent: parent)
  }
}

@available(iOS 26.0, *)
private final class CatalogTabView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private let host: CatalogTabHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    host = CatalogTabHost(frame: frame)
    channel = FlutterMethodChannel(name: "\(CatalogTabs.viewType)/\(id)", binaryMessenger: messenger)
    super.init()
    let tabs = host.tabs
    tabs.mode = .tabBar
    // Confine the compact bottom tab arrangement to this control on iPad.
    tabs.traitOverrides.horizontalSizeClass = .compact
    let symbols = ["house", "film", "tv", "antenna.radiowaves.left.and.right", "bookmark"]
    let labels = args["labels"] as? [String] ?? []
    tabs.viewControllers = zip(labels, symbols).enumerated().map { index, pair in
      let content = UIViewController()
      content.view.backgroundColor = .clear
      let image = UIImage(systemName: pair.1)
      content.tabBarItem = UITabBarItem(title: pair.0, image: image, selectedImage: UIImage(systemName: pair.1 + ".fill") ?? image)
      content.tabBarItem.accessibilityIdentifier = "catalog-tab-\(index)"
      return content
    }
    tabs.delegate = self
    setSelection(args["index"])
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "select" else { result(FlutterMethodNotImplemented); return }
      self?.setSelection(call.arguments)
      result(nil)
    }
  }
  private func setSelection(_ value: Any?) {
    if let index = value as? Int, let pages = host.tabs.viewControllers, pages.indices.contains(index), index != host.tabs.selectedIndex {
      host.tabs.selectedIndex = index
    }
  }
  func view() -> UIView { host }
  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    channel.invokeMethod("selected", arguments: tabBarController.selectedIndex)
  }
  deinit { channel.setMethodCallHandler(nil) }
}
