package app.bechiflix.bechi_player_prototype

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JsResult
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import org.json.JSONObject

/** Only provider preparation lives here. Dart's private relay feeds libmpv. */
class HostedSource(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "app.bechiflix.native/hosted")
    private val handler = Handler(Looper.getMainLooper())
    private val origin = "https://bechi-flix.137-131-229-110.sslip.io"
    private val players = setOf("xn--tckasiu6cvova0eb5fua2449g98vg.best", "xn--80adalaab0boiodbce7addhh.delivery")
    private val origins = (players + setOf("superflixapi.boats", "abyssplayer.com", "challenges.cloudflare.com", URI(origin).host)).map { "https://$it" }.toSet()
    private var web: WebView? = null
    private var injection: ScriptHandler? = null
    private var target = JSONObject()
    private var pending: MethodChannel.Result? = null
    private var timeout: Runnable? = null
    private var confirmation: FrameLayout? = null
    private var rootDocument: String? = null
    private var reusable = false
    private var started = 0L
    private val frames = mutableMapOf<String, Frame>()
    private val reads = mutableMapOf<String, Read>()
    private data class Frame(val reply: JavaScriptReplyProxy, val host: String)
    private data class Read(val result: MethodChannel.Result, val frame: String, val host: String, val timeout: Runnable)

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "prepare" -> prepare(args, result)
                "read" -> read(args, result)
                "close" -> { if (args["epoch"] == target.optString("epoch")) close(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (pending === result) { pending = null; cancelTimeout(); reusable = false }
            fail(result, "SOURCE_INPUT")
        }
    }

    private fun prepare(args: Map<*, *>, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            fail(result, "SOURCE_WEBVIEW_UPDATE"); return
        }
        val script = args["script"] as? String ?: error("script")
        val bridge = args["bridge"] as? String ?: error("bridge")
        require(script.toByteArray().size < 100000 && bridge.toByteArray().size < 30000)
        val address = args["url"] as? String ?: error("url")
        val url = URI(address)
        require(url.scheme == "https" && url.userInfo == null && url.port == -1 && url.rawQuery == null && url.rawFragment == null)
        val epoch = args["epoch"] as? String ?: error("epoch")
        require(epoch.length == 36 && UUID.fromString(epoch).toString() == epoch.lowercase(Locale.ROOT))
        val title = args["expectedTitle"] as? String ?: error("title")
        require(title.isNotBlank() && title.length <= 300)
        val kind = args["kind"] as? String ?: error("kind")
        val movie = kind == "superflix" && url.path.startsWith("/filme/")
        val parts = url.path.trim('/').split('/')
        if (kind == "superflix") {
            require(url.host == "superflixapi.boats" && Regex("^/(serie/[1-9][0-9]{0,8}/[1-9][0-9]?/[1-9][0-9]{0,2}|filme/[1-9][0-9]{0,8})$").matches(url.path))
        } else {
            require(kind == "c7" && url.host == "abyssplayer.com" && Regex("^/[A-Za-z0-9]{5,32}$").matches(url.path))
        }
        val root = if (kind == "c7" || movie) address else "https://superflixapi.boats/serie/${parts[1]}"
        val retained = if (reusable && target.optString("root") == root) rootDocument?.let { frames[it] } else null
        pending?.let { fail(it, "SOURCE_REPLACED") }; pending = null
        cancelReads("SOURCE_REPLACED")
        dismissConfirmation()
        target = JSONObject().put("epoch", epoch).put("kind", kind).put("url", address).put("root", root)
            .put("expectedTitle", title).put("movie", movie)
            .put("season", if (kind == "superflix") if (movie) 0 else parts[2].toInt() else (args["season"] as? Number)?.toInt() ?: 1)
            .put("episode", if (kind == "superflix") if (movie) 0 else parts[3].toInt() else (args["episode"] as? Number)?.toInt() ?: 1)
        started = System.currentTimeMillis(); frames.clear(); rootDocument = null; reusable = false
        pending = result; armTimeout(); diagnostic("prepare")
        val view = web ?: createWebView().also { web = it }
        injection?.remove()
        val binary = WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_ARRAY_BUFFER)
        val source = "window.__bechiHostedTarget=$target;\n" + bridge.replace("__BECHI_BINARY__", binary.toString()) + "\n" +
            script.replace("window.webkit?.messageHandlers?.bechiHosted?.postMessage", "window.__bechiAndroidPost")
        injection = WebViewCompat.addDocumentStartJavaScript(view, source, origins)
        attachHidden()
        if (retained != null) {
            try { retained.reply.postMessage(JSONObject().put("type", "configure").put("target", target).toString()) }
            catch (_: Exception) { loadShell() }
            handler.postDelayed({ if (target.optString("epoch") == epoch && pending != null && rootDocument == null) loadShell() }, 1800)
        } else loadShell()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView {
        val view = WebView(activity)
        view.setBackgroundColor(Color.BLACK)
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        view.settings.mediaPlaybackRequiresUserGesture = false
        view.settings.javaScriptCanOpenWindowsAutomatically = false
        view.settings.setSupportMultipleWindows(true)
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
        WebViewCompat.addWebMessageListener(view, "bechiHosted", origins) { _, message, sourceOrigin, _, reply ->
            receive(message, sourceOrigin, reply)
        }
        view.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, message: android.os.Message?): Boolean = false
            override fun onJsAlert(view: WebView?, url: String?, message: String?, result: JsResult?): Boolean { result?.cancel(); return true }
            override fun onJsConfirm(view: WebView?, url: String?, message: String?, result: JsResult?): Boolean { result?.cancel(); return true }
        }
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean =
                request == null || !allowedNavigation(request.url, request.isForMainFrame)
            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                handler?.cancel()
                if (pending != null && error?.url?.let { isSourceDocument(Uri.parse(it)) } == true) {
                    finishFailure("SOURCE_TLS")
                }
            }
            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (pending == null || request == null || !isSourceDocument(request.url)) return
                val code = when (error?.errorCode) {
                    WebViewClient.ERROR_HOST_LOOKUP -> "SOURCE_DNS"
                    WebViewClient.ERROR_CONNECT, WebViewClient.ERROR_IO -> "SOURCE_CONNECTION"
                    WebViewClient.ERROR_TIMEOUT -> "SOURCE_TIMEOUT"
                    WebViewClient.ERROR_FAILED_SSL_HANDSHAKE -> "SOURCE_TLS"
                    else -> return
                }
                finishFailure(code)
            }
            override fun onPageFinished(view: WebView?, url: String?) { diagnostic("shell_loaded") }
        }
        return view
    }

    private fun isSourceDocument(uri: Uri): Boolean {
        if (uri.scheme != "https" || uri.userInfo != null || uri.port != -1) return false
        val address = uri.buildUpon().clearQuery().fragment(null).build().toString()
        if (address == "$origin/native-source-shell.html" ||
            address == target.optString("root") || address == target.optString("url")) return true
        return target.optString("kind") == "superflix" && uri.host in players &&
            Regex("^/video/[a-f0-9]{32}$").matches(uri.path.orEmpty())
    }

    private fun loadShell() {
        val root = target.optString("root")
        web?.loadUrl(Uri.parse("$origin/native-source-shell.html").buildUpon().fragment(root).build().toString())
    }

    private fun allowedNavigation(uri: Uri, main: Boolean): Boolean {
        if (uri.toString() == "about:blank") return true
        if (uri.scheme != "https" || uri.userInfo != null || uri.port != -1) return false
        val host = uri.host ?: return false
        val path = uri.path ?: return false
        if (main) return host == URI(origin).host && path == "/native-source-shell.html" && uri.query == null
        return host == "challenges.cloudflare.com" ||
            host == "superflixapi.boats" && (path.startsWith("/serie/") || path.startsWith("/filme/") || path.startsWith("/player/redirect") || path.startsWith("/cdn-cgi/")) ||
            host in players && Regex("^/video/[a-f0-9]{32}$").matches(path) ||
            target.optString("kind") == "c7" && uri.toString() == target.optString("url")
    }

    private fun receive(message: WebMessageCompat, origin: Uri, reply: JavaScriptReplyProxy) {
        try {
            var bytes: ByteArray? = null
            val data = if (message.type == WebMessageCompat.TYPE_ARRAY_BUFFER) {
                val packet = message.arrayBuffer
                require(packet.size in 5..(16777216 + 4100))
                val length = ByteBuffer.wrap(packet, 0, 4).order(ByteOrder.LITTLE_ENDIAN).int
                require(length in 1..4096 && 4 + length <= packet.size)
                bytes = packet.copyOfRange(4 + length, packet.size)
                JSONObject(String(packet, 4, length, Charsets.UTF_8))
            } else {
                val text = message.data ?: return
                require(text.length < 24000000)
                JSONObject(text)
            }
            if (data.optString("epoch") != target.optString("epoch") || target.optString("epoch").isEmpty()) return
            val url = URI(data.optString("documentURL"))
            if (url.scheme != "https" || origin.scheme != "https" || url.host != origin.host || url.port != -1 || origin.port !in listOf(-1, 443)) return
            val host = url.host ?: return
            val type = data.optString("type")
            if (host == "challenges.cloudflare.com") { if (type == "human") showConfirmation(); return }
            val canonical = "https://$host${url.path}"
            val root = canonical == target.optString("root") || canonical == target.optString("url")
            val player = target.optString("kind") == "c7" && root || host in players && Regex("^/video/[a-f0-9]{32}$").matches(url.path)
            if (!root && !player) return
            val doc = data.optString("document")
            if (doc.isEmpty() || doc.length > 100) return
            if (type == "readResult" || type == "readError") {
                val read = reads[data.optString("request")] ?: return
                if (read.frame != doc || read.host != host || !player) return
                reads.remove(data.optString("request")); handler.removeCallbacks(read.timeout)
                if (type == "readError") { fail(read.result, "SOURCE_READ"); return }
                try {
                    val payload = data.getJSONObject("payload")
                    val body = bytes ?: Base64.decode(payload.optString("data"), Base64.DEFAULT)
                    require(body.size <= 16777216)
                    read.result.success(mapOf("status" to payload.getInt("status"), "type" to payload.optString("type", "application/octet-stream"),
                        "range" to if (payload.isNull("range")) null else payload.optString("range"), "data" to body))
                } catch (_: Exception) { fail(read.result, "SOURCE_READ") }
                return
            }
            frames[doc] = Frame(reply, host)
            if (root) rootDocument = doc
            when (type) {
                "loaded" -> diagnostic("document_loaded", mapOf("scope" to if (root) "root" else "player"))
                "human" -> showConfirmation()
                "validated" -> { dismissConfirmation(); phase("episode"); if (timeout == null) armTimeout(); diagnostic("validated") }
                "failure" -> { val code = data.optString("code"); if (Regex("^SOURCE_[A-Z_]+$").matches(code)) finishFailure(code) }
                "ready" -> {
                    if (!player || !safeMedia(data.optString("url"))) return
                    val variants = data.optJSONArray("variants") ?: return
                    if (variants.length() !in 1..12) return
                    val rows = mutableListOf<Map<String, Any>>()
                    for (i in 0 until variants.length()) {
                        val row = variants.getJSONObject(i)
                        if (!safeMedia(row.optString("url"))) return
                        if (row.getString("url").length > 8192 || row.optInt("height", 0) !in 0..4320) return
                        rows.add(mapOf("url" to row.getString("url"), "height" to row.optInt("height", 0), "label" to row.optString("label", "Automática").take(100)))
                    }
                    val format = data.optString("format")
                    if (format !in setOf("hls", "mp4")) return
                    val callback = pending ?: return
                    pending = null; cancelTimeout(); dismissConfirmation(); reusable = true
                    diagnostic("ready", mapOf("format" to format, "variants" to rows.size))
                    callback.success(mapOf("frame" to doc, "url" to data.getString("url"), "format" to format, "variants" to rows))
                }
            }
        } catch (_: Exception) { /* Untrusted or obsolete frame messages are ignored. */ }
    }

    private fun read(args: Map<*, *>, result: MethodChannel.Result) {
        if (args["epoch"] != target.optString("epoch")) { fail(result, "SOURCE_CLOSED"); return }
        val doc = args["frame"] as? String ?: error("frame")
        val frame = frames[doc] ?: run { fail(result, "SOURCE_READ"); return }
        val url = args["url"] as? String ?: error("url")
        val range = args["range"] as? String
        require(safeMedia(url) && url.length <= 8192 && (range == null || Regex("^bytes=[0-9]+-[0-9]*$").matches(range)))
        if (reads.size >= 8) { fail(result, "SOURCE_BUSY"); return }
        val id = UUID.randomUUID().toString()
        val deadline = Runnable { reads.remove(id)?.let { fail(it.result, "SOURCE_READ_TIMEOUT") } }
        reads[id] = Read(result, doc, frame.host, deadline); handler.postDelayed(deadline, 30000)
        try {
            frame.reply.postMessage(JSONObject().put("type", "read").put("request", id).put("epoch", target.getString("epoch"))
                .put("url", url).put("range", range ?: JSONObject.NULL).toString())
        } catch (_: Exception) { reads.remove(id); handler.removeCallbacks(deadline); fail(result, "SOURCE_READ") }
    }

    private fun safeMedia(value: String): Boolean = try {
        val url = URI(value); val host = url.host?.lowercase(Locale.ROOT) ?: ""
        url.scheme == "https" && url.userInfo == null && url.port == -1 && url.rawFragment == null && host.contains('.') &&
            !Regex("^[0-9.]+$").matches(host) && !host.contains(':') && !host.endsWith(".local") && !host.endsWith(".localhost")
    } catch (_: Exception) { false }

    private fun content(): ViewGroup? = activity.findViewById(android.R.id.content)
    private fun attachHidden() {
        if (confirmation != null) return
        val view = web ?: return
        val parent = content() ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        view.isFocusable = false
        parent.addView(view, 0, FrameLayout.LayoutParams(-1, -1))
        diagnostic("surface", mapOf("attached" to view.isAttachedToWindow, "width" to parent.width, "height" to parent.height))
    }

    private fun showConfirmation() {
        if (confirmation != null || pending == null) return
        val view = web ?: return; val parent = content() ?: return
        cancelTimeout(); phase("human"); diagnostic("human")
        val overlay = FrameLayout(activity).apply { setBackgroundColor(Color.BLACK) }
        val column = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(12, 8, 12, 8) }
        header.addView(TextView(activity).apply { text = "Confirmação da fonte"; setTextColor(Color.WHITE); textSize = 18f }, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(Button(activity).apply { text = "Cancelar"; setOnClickListener { finishFailure("VERIFICATION_CANCELLED") } })
        column.addView(header)
        (view.parent as? ViewGroup)?.removeView(view)
        view.isFocusable = true; view.isFocusableInTouchMode = true
        column.addView(view, LinearLayout.LayoutParams(-1, 0, 1f)); overlay.addView(column, FrameLayout.LayoutParams(-1, -1))
        confirmation = overlay; parent.addView(overlay, FrameLayout.LayoutParams(-1, -1)); view.requestFocus()
    }

    private fun dismissConfirmation() {
        val overlay = confirmation ?: return
        (web?.parent as? ViewGroup)?.removeView(web)
        (overlay.parent as? ViewGroup)?.removeView(overlay); confirmation = null
        attachHidden()
    }
    private fun phase(value: String) { channel.invokeMethod("phase", mapOf("epoch" to target.optString("epoch"), "phase" to value)) }
    private fun diagnostic(stage: String, extra: Map<String, Any> = emptyMap()) {
        channel.invokeMethod("diagnostic", extra + mapOf("epoch" to target.optString("epoch"), "kind" to target.optString("kind"),
            "stage" to stage, "elapsed_ms" to System.currentTimeMillis() - started))
    }
    private fun cancelTimeout() { timeout?.let { handler.removeCallbacks(it) }; timeout = null }
    private fun armTimeout() { cancelTimeout(); timeout = Runnable { finishFailure("SOURCE_TIMEOUT") }.also { handler.postDelayed(it, 240000) } }
    private fun fail(result: MethodChannel.Result, code: String) { result.error(code, "A fonte não concluiu a preparação. Tente novamente.", null) }
    private fun finishFailure(code: String) { diagnostic("failure", mapOf("code" to code)); reusable = false; cancelTimeout(); dismissConfirmation(); pending?.let { pending = null; fail(it, code) } }
    private fun cancelReads(code: String) { val old = reads.values.toList(); reads.clear(); old.forEach { handler.removeCallbacks(it.timeout); fail(it.result, code) } }
    private fun close() {
        cancelTimeout(); pending?.let { pending = null; fail(it, "SOURCE_CLOSED") }; cancelReads("SOURCE_CLOSED")
        dismissConfirmation(); injection?.remove(); injection = null
        web?.let { it.stopLoading(); (it.parent as? ViewGroup)?.removeView(it); it.destroy() }
        web = null; target = JSONObject(); frames.clear(); rootDocument = null; reusable = false
    }
    fun dispose() { close(); channel.setMethodCallHandler(null) }
}
