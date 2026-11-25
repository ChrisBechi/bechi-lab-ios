import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'bechi_api.dart';

const _audioChannel = MethodChannel('app.bechiflix.native/audio');
final _audioLeases = <Player, String>{};
String _audioLease() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final value = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}

Future<void> releaseNativeEngineAudio(Player player) async {
  final lease = _audioLeases.remove(player);
  if (lease == null) return;
  try {
    await _audioChannel.invokeMethod<void>('release', {'lease': lease});
  } on PlatformException {
    /* The OS also releases the session at app exit. */
  }
}

Future<File>? _caBundle;
Future<File> _certificates() => _caBundle ??= () async {
  final directory = await Directory.systemTemp.createTemp('bechi-native-ca-');
  final asset = await rootBundle.load('assets/certificates/cacert.pem');
  return File('${directory.path}/cacert.pem').writeAsBytes(
    asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    flush: true,
  );
}();

/// Keep transport verification explicit, including older FFmpeg builds whose
/// default differs from current mpv. These are player options, never JS eval.
Future<void> configureNativeEngine(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw UnsupportedError('Este aplicativo exige o motor nativo de vídeo.');
  }
  if (Platform.isIOS) {
    final lease = _audioLeases.putIfAbsent(player, _audioLease);
    try {
      await _audioChannel.invokeMethod<dynamic>('activate', {'lease': lease});
    } on PlatformException {
      throw const ApiFailure(
        'AUDIO_SESSION',
        'Não foi possível ativar a saída de áudio.',
      );
    }
  }
  await native.setProperty('tls-verify', 'yes');
  await native.setProperty('tls-ca-file', (await _certificates()).path);
  await native.setProperty('hls-bitrate', 'max');
  await native.setProperty('network-timeout', '60');
  await native.setProperty('alang', 'pt,por,pt-BR,pt-PT');
}
