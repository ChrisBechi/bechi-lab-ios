import 'dart:io';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

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
  await native.setProperty('tls-verify', 'yes');
  await native.setProperty('tls-ca-file', (await _certificates()).path);
  await native.setProperty('hls-bitrate', 'max');
  await native.setProperty('network-timeout', '60');
  await native.setProperty('alang', 'pt,por,pt-BR,pt-PT');
}
