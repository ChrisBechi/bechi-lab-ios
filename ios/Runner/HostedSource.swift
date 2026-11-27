import Flutter
import UIKit
import WebKit

@available(iOS 14.0, *)
final class HostedSource: NSObject, FlutterPlugin, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
  private var web: WKWebView?
  private var frames: [String: WKFrameInfo] = [:]
  private var target: [String: Any] = [:]
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var awaitingSourceResponse: String?
  private var verification: UINavigationController?
  private var channel: FlutterMethodChannel?
  private var reusable = false
  private var sourceValidated = false
  private var startedAt = Date()
  private let origin = "https://bechi-flix.137-131-229-110.sslip.io"
  private let players = Set(["xn--tckasiu6cvova0eb5fua2449g98vg.best", "xn--80adalaab0boiodbce7addhh.delivery"])

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HostedSource()
    let channel = FlutterMethodChannel(name: "app.bechiflix.native/hosted", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepare":
      guard let args = call.arguments as? [String: Any], let script = args["script"] as? String, script.utf8.count < 100000,
            let urlText = args["url"] as? String, let url = URL(string: urlText), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
            let epoch = args["epoch"] as? String, UUID(uuidString: epoch) != nil,
            let expected = args["expectedTitle"] as? String, !expected.isEmpty, expected.count < 300,
            let kind = args["kind"] as? String, ["superflix", "c7"].contains(kind) else { fail(result, "SOURCE_INPUT"); return }
      let path = url.path
      if kind == "superflix" {
        guard url.host == "superflixapi.boats", path.range(of: "^/(serie/[1-9][0-9]{0,8}/[1-9][0-9]?/[1-9][0-9]{0,2}|filme/[1-9][0-9]{0,8})$", options: .regularExpression) != nil else { fail(result, "SOURCE_INPUT"); return }
      } else {
        guard url.host == "abyssplayer.com", path.range(of: "^/[A-Za-z0-9]{5,32}$", options: .regularExpression) != nil else { fail(result, "SOURCE_INPUT"); return }
      }
      let components = path.split(separator: "/"), movie = components.first == "filme"
      let root = kind == "c7" || movie ? urlText : "https://superflixapi.boats/serie/\(components[1])"
      var config = args; config.removeValue(forKey: "script"); config["root"] = root; config["movie"] = movie
      if kind == "superflix" { config["season"] = movie ? 0 : Int(components[2])!; config["episode"] = movie ? 0 : Int(components[3])! }
      guard let data = try? JSONSerialization.data(withJSONObject: config), let json = String(data: data, encoding: .utf8) else { fail(result, "SOURCE_INPUT"); return }
      let retainedFrame = reusable && target["root"] as? String == root ? framesForRoot(root) : nil
      awaitingSourceResponse = nil
      reusable = false; sourceValidated = false
      pending?(FlutterError(code: "SOURCE_REPLACED", message: "A solicitação da fonte mudou.", details: nil))
      pending = result; target = config; frames.removeAll(); timeout?.cancel(); startedAt = Date()
      diagnostic("prepare")
      let work = DispatchWorkItem { [weak self] in self?.finishFailure("SOURCE_TIMEOUT") }
      timeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 240, execute: work)
      if web == nil {
        let controller = WKUserContentController(); controller.add(self, name: "bechiHosted")
        let configuration = WKWebViewConfiguration(); configuration.userContentController = controller
        configuration.websiteDataStore = .default(); configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true; configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self; web = view
      }
      guard let view = web else { finishFailure("SOURCE_UNAVAILABLE"); return }
      view.configuration.userContentController.removeAllUserScripts()
      view.configuration.userContentController.addUserScript(WKUserScript(source: "window.__bechiHostedTarget=\(json);\n" + script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
      attachHidden()
      // Preserve the provider's own WK data store; never import browser cookies.
      if let rootFrame = retainedFrame {
        view.callAsyncJavaScript("window.__bechiConfigureHosted(config)", arguments: ["config": config], in: rootFrame, in: .page) { _ in }
      } else {
        if kind == "superflix" {
          awaitingSourceResponse = epoch
          DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self = self, self.pending != nil, self.awaitingSourceResponse == epoch else { return }
            self.finishFailure("SOURCE_NO_RESPONSE")
          }
        }
        var shell = URLComponents(string: origin + "/native-source-shell.html")!
        shell.fragment = root
        view.load(URLRequest(url: shell.url!))
      }
    case "showSource":
      guard let args = call.arguments as? [String: Any], args["epoch"] as? String == target["epoch"] as? String,
            pending != nil else { result(nil); return }
      showVerification(manual: true)
      result(nil)
    case "read":
      guard let args = call.arguments as? [String: Any], args["epoch"] as? String == target["epoch"] as? String, let key = args["frame"] as? String, let frame = frames[key], let value = args["url"] as? String,
            let url = URL(string: value), safeMedia(url), value.utf8.count <= 8192, let view = web else { fail(result, "SOURCE_READ"); return }
      let range = args["range"] as? String
      if let range = range, range.range(of: "^bytes=[0-9]+-[0-9]*$", options: .regularExpression) == nil { fail(result, "SOURCE_RANGE"); return }
      view.callAsyncJavaScript("return await window.__bechiReadHosted(url, range)", arguments: ["url": value, "range": range as Any? ?? NSNull()], in: frame, in: .page) { value in
        switch value {
        case .success(let payload):
          guard var payload = payload as? [String: Any], let encoded = payload["data"] as? String, encoded.utf8.count <= 23000000,
                let bytes = Data(base64Encoded: encoded), bytes.count <= 16777216 else { self.fail(result, "SOURCE_READ"); return }
          // Binary channel payload avoids a second base64 copy in Dart.
          payload["data"] = FlutterStandardTypedData(bytes: bytes)
          result(payload)
        case .failure: self.fail(result, "SOURCE_READ")
        }
      }
    case "close":
      guard let args = call.arguments as? [String: Any], args["epoch"] as? String == target["epoch"] as? String else { result(nil); return }
      awaitingSourceResponse = nil; timeout?.cancel(); timeout = nil
      pending?(FlutterError(code: "SOURCE_CLOSED", message: "Reprodução encerrada.", details: nil)); pending = nil
      dismissVerification(); web?.stopLoading(); web?.removeFromSuperview()
      web?.configuration.userContentController.removeScriptMessageHandler(forName: "bechiHosted")
      web = nil; target = [:]; reusable = false; frames.removeAll(); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func framesForRoot(_ root: String) -> WKFrameInfo? {
    frames.values.first { frame in
      guard let url = frame.request.url, url.scheme == "https", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
      parts.query = nil; parts.fragment = nil
      return parts.url?.absoluteString == root || parts.url?.absoluteString == target["url"] as? String
    }
  }
  private func safeMedia(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil, let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "localhost" else { return false }
    return host.range(of: "^[0-9.]+$", options: .regularExpression) == nil && !host.contains(":")
  }
  private func rootController() -> UIViewController? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
  }
  private func diagnostic(_ stage: String, _ extra: [String: Any] = [:]) {
    var info = extra
    info["epoch"] = target["epoch"]; info["kind"] = target["kind"]; info["stage"] = stage
    info["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
    channel?.invokeMethod("diagnostic", arguments: info)
  }
  private func attachHidden() {
    guard verification == nil else { return }
    guard let view = web, let root = rootController(), let parent = root.view.superview else {
      diagnostic("surface_missing", ["root_available": rootController() != nil]); return
    }
    view.removeFromSuperview(); view.frame = parent.bounds; view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.isUserInteractionEnabled = false; parent.insertSubview(view, belowSubview: root.view)
    diagnostic("surface", ["attached": view.window != nil, "width": Int(view.bounds.width), "height": Int(view.bounds.height)])
  }
  private func showVerification(manual: Bool = false) {
    guard verification == nil, pending != nil, let view = web, let root = rootController() else { return }
    awaitingSourceResponse = nil
    diagnostic(manual ? "source_opened_by_user" : "human")
    if !manual {
      channel?.invokeMethod("phase", arguments: ["epoch": target["epoch"] ?? "", "phase": "human"])
      timeout?.cancel(); timeout = nil
    }
    for frame in frames.values {
      view.callAsyncJavaScript("if (document.documentElement) document.documentElement.style.visibility = 'visible'", arguments: [:], in: frame, in: .page) { _ in }
    }
    let screen = HostedVerificationController(web: view, manual: manual) { [weak self] in
      if manual { self?.dismissVerification() }
      else { self?.finishFailure("VERIFICATION_CANCELLED") }
    }
    let navigation = UINavigationController(rootViewController: screen); navigation.modalPresentationStyle = .fullScreen
    navigation.isModalInPresentation = true; verification = navigation
    var presenter = root; while let current = presenter.presentedViewController { presenter = current }
    presenter.present(navigation, animated: true)
  }
  private func dismissVerification() {
    guard let screen = verification else { return }; verification = nil
    screen.dismiss(animated: false) { [weak self] in self?.attachHidden() }
  }
  private func fail(_ result: FlutterResult, _ code: String) { result(FlutterError(code: code, message: "A fonte não concluiu a preparação. Tente novamente.", details: nil)) }
  private func finishFailure(_ code: String) { diagnostic("failure", ["code": code]); reusable = false; timeout?.cancel(); timeout = nil; dismissVerification(); guard let callback = pending else { return }; pending = nil; fail(callback, code) }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let data = message.body as? [String: Any], let epoch = data["epoch"] as? String, epoch == target["epoch"] as? String,
          let type = data["type"] as? String, let address = data["documentURL"] as? String, let url = URL(string: address), url.scheme == "https", let host = url.host,
          message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == host else { return }
    if host == "challenges.cloudflare.com" { if type == "human" { showVerification() }; return }
    var location = URLComponents(url: url, resolvingAgainstBaseURL: false)!; location.query = nil; location.fragment = nil
    let canonical = location.url!.absoluteString
    let root = canonical == target["root"] as? String || canonical == target["url"] as? String
    let player = target["kind"] as? String == "c7" && root || players.contains(host) && url.path.range(of: "^/video/[a-f0-9]{32}$", options: .regularExpression) != nil
    guard root || player else { return }
    awaitingSourceResponse = nil
    if type == "human" { showVerification(); return }
    if let key = data["document"] as? String, key.count < 100 { frames[key] = message.frameInfo }
    if type == "loaded" {
      diagnostic("document_loaded", ["scope": root ? "root" : "player"])
      if root {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
          guard let self = self, self.target["epoch"] as? String == epoch, self.pending != nil,
                self.verification == nil, !self.sourceValidated else { return }
          self.channel?.invokeMethod("phase", arguments: ["epoch": epoch, "phase": "waiting"])
        }
      }
      return
    }
    if type == "validated" {
      sourceValidated = true
      diagnostic("validated")
      dismissVerification(); channel?.invokeMethod("phase", arguments: ["epoch": epoch, "phase": "episode"])
      if pending != nil && timeout == nil { let work = DispatchWorkItem { [weak self] in self?.finishFailure("SOURCE_TIMEOUT") }; timeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 240, execute: work) }
      return
    }
    if type == "failure", let code = data["code"] as? String, code.range(of: "^SOURCE_[A-Z_]+$", options: .regularExpression) != nil { finishFailure(code); return }
    guard type == "ready", player, let value = data["url"] as? String, let media = URL(string: value), safeMedia(media), let key = data["document"] as? String,
          let variants = data["variants"] as? [[String: Any]], !variants.isEmpty, variants.count <= 12 else { return }
    timeout?.cancel(); timeout = nil; dismissVerification()
    guard let callback = pending else { return }; pending = nil
    reusable = true
    diagnostic("ready", ["format": data["format"] ?? "hls", "variants": variants.count])
    callback(["frame": key, "url": value, "variants": variants, "format": data["format"] ?? "hls"])
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard navigationAction.targetFrame != nil, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, let host = url.host else { decisionHandler(.cancel); return }
    if navigationAction.targetFrame?.isMainFrame == true {
      let shell = host == URL(string: origin)?.host && url.path == "/native-source-shell.html" && url.query == nil
      decisionHandler(shell ? .allow : .cancel)
      return
    }
    let allowed = host == "challenges.cloudflare.com" || host == "superflixapi.boats" && (url.path.hasPrefix("/serie/") || url.path.hasPrefix("/filme/") || url.path.hasPrefix("/player/redirect") || url.path.hasPrefix("/cdn-cgi/")) || players.contains(host) && url.path.range(of: "^/video/[a-f0-9]{32}$", options: .regularExpression) != nil || target["kind"] as? String == "c7" && url.absoluteString == target["url"] as? String
    decisionHandler(allowed || isC7Document(url) ? .allow : .cancel)
  }
  private func isC7Document(_ url: URL) -> Bool {
    guard target["kind"] as? String == "c7", let expected = target["url"] as? String,
          let permitted = URL(string: expected), url.scheme == "https", url.host == permitted.host,
          url.port == nil, url.user == nil, url.password == nil else { return false }
    return url.path == permitted.path
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard pending != nil, let response = navigationResponse.response as? HTTPURLResponse,
          let url = response.url else { decisionHandler(.allow); return }
    let canonical = "https://" + (url.host ?? "") + url.path
    let source = isC7Document(url) || canonical == target["root"] as? String || canonical == target["url"] as? String
    guard source else { decisionHandler(.allow); return }
    awaitingSourceResponse = nil
    diagnostic("source_response", ["status": response.statusCode])
    let challenge = response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
    if challenge {
      // The real widget requests interaction separately if a tap is required.
      decisionHandler(.allow)
      return
    }
    switch response.statusCode {
    case 401, 403, 404, 410, 451, 429, 500...599:
      decisionHandler(.cancel)
      let code: String
      switch response.statusCode {
      case 401, 403, 451: code = "SOURCE_ACCESS"
      case 404, 410: code = "SOURCE_NOT_FOUND"
      default: code = "SOURCE_UNAVAILABLE"
      }
      finishFailure(code)
    default: decisionHandler(.allow)
    }
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    let code = (error as NSError).code
    diagnostic("navigation_failure", ["os_code": code])
    switch code {
    case NSURLErrorCancelled: break
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: finishFailure("SOURCE_DNS")
    case NSURLErrorTimedOut: finishFailure("SOURCE_TIMEOUT")
    case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted: finishFailure("SOURCE_TLS")
    default: finishFailure("SOURCE_CONNECTION")
    }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { diagnostic("shell_loaded") }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finishFailure("SOURCE_PROCESS") }
}

@available(iOS 14.0, *)
private final class HostedVerificationController: UIViewController {
  let web: WKWebView; let manual: Bool; let cancel: () -> Void
  init(web: WKWebView, manual: Bool, cancel: @escaping () -> Void) { self.web = web; self.manual = manual; self.cancel = cancel; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Unsupported") }
  override func viewDidLoad() {
    super.viewDidLoad(); title = manual ? "Página da fonte" : "Confirmação da fonte"; view.backgroundColor = .black
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: manual ? "Voltar" : "Cancelar", style: .plain, target: self, action: #selector(close))
    web.removeFromSuperview(); web.isUserInteractionEnabled = true; web.frame = view.bounds; web.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(web)
  }
  @objc private func close() { cancel() }
}
