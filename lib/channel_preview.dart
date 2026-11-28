import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'bechi_api.dart';
import 'native_engine.dart';
import 'native_source.dart';
import 'source_case.dart';

class ChannelPreview extends StatefulWidget {
  const ChannelPreview({
    super.key,
    required this.api,
    required this.source,
    required this.onExpand,
  });
  final BechiApi api;
  final SourceCase source;
  final VoidCallback onExpand;
  @override
  State<ChannelPreview> createState() => _ChannelPreviewState();
}

class _ChannelPreviewState extends State<ChannelPreview> {
  final player = Player(
    configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
  );
  late final controller = VideoController(player);
  late final session = NativeSourceSession(
    widget.api,
    widget.source,
    onStatus: (_) {},
  );
  late Future<void> ready = start();
  Future<void> start() async {
    final stream = await session.open();
    if (!mounted) return;
    await configureNativeEngine(player);
    if (!mounted) return;
    await player.open(Media(stream.url, httpHeaders: stream.headers));
  }

  @override
  void dispose() {
    session.scope.cancel();
    unawaited(session.close());
    unawaited(
      player.dispose().whenComplete(() => releaseNativeEngineAudio(player)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Colors.black,
      child: FutureBuilder(
        future: ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => ready = start()),
                child: const Text('Tentar prévia novamente'),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return Semantics(
            label: 'Abrir transmissão em tela cheia',
            button: true,
            child: GestureDetector(
              onTap: widget.onExpand,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(controller: controller, controls: NoVideoControls),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.fullscreen),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
