package app.bechiflix.bechi_player_prototype

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hostedSource: HostedSource? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hostedSource = HostedSource(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        hostedSource?.dispose()
        hostedSource = null
        super.onDestroy()
    }
}
