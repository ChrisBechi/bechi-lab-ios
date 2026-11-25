import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'bechi_api.dart';
import 'native_source.dart';
import 'native_engine.dart';
import 'source_case.dart';

class NativePlayerPage extends StatefulWidget {
  const NativePlayerPage({
    super.key,
    required this.api,
    required this.source,
    this.player,
  });
  final BechiApi api;
  final SourceCase source;
  // Tests can supply a real native engine; this route owns its lifecycle.
  final Player? player;
  @override
  State<NativePlayerPage> createState() => NativePlayerPageState();
}

class NativePlayerPageState extends State<NativePlayerPage> {
  late final Player player =
      widget.player ??
      Player(
        configuration: const PlayerConfiguration(
          bufferSize: 16 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
          title: 'Bechi Native',
        ),
      );
  late final VideoController controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );
  late final NativeSourceSession session = NativeSourceSession(
    widget.api,
    widget.source,
    onStatus: (message) {
      if (mounted) setState(() => status = message);
    },
  );
  final List<StreamSubscription<dynamic>> subscriptions = [];
  NativePlayback? playback;
  String status = 'Preparando reprodução…', quality = 'Automática';
  String? error;
  bool controls = true, busy = false, closing = false, audioChosen = false;
  int revision = 0;
  Timer? hideTimer, progressTimer;
  double? dragging;
  final startup = Stopwatch();
  int? firstFrameMs;
  bool mediaLoaded = false;
  @override
  void initState() {
    super.initState();
    subscriptions.add(
      player.stream.position.listen((v) {
        if (closing) return;
        session.position = v;
        if (mediaLoaded &&
            firstFrameMs == null &&
            v.inMilliseconds > 0 &&
            (player.state.width ?? 0) > 0) {
          firstFrameMs = startup.elapsedMilliseconds;
        }
        if (mounted) setState(() {});
      }),
    );
    subscriptions.add(
      player.stream.duration.listen((v) {
        if (closing) return;
        session.duration = v;
        if (mounted) setState(() {});
      }),
    );
    subscriptions.add(
      player.stream.buffering.listen((_) {
        if (mounted) setState(() {});
      }),
    );
    subscriptions.add(
      player.stream.playing.listen((v) {
        if (mounted) {
          setState(() {});
          if (v) scheduleHide();
        }
      }),
    );
    subscriptions.add(
      player.stream.error.listen((message) {
        if (mounted) {
          setState(
            () =>
                error = message.replaceAll(RegExp(r'https?://\S+'), '[mídia]'),
          );
        }
      }),
    );
    subscriptions.add(
      player.stream.tracks.listen((tracks) {
        if (!audioChosen) {
          final preferred = tracks.audio
              .where(
                (t) =>
                    RegExp(
                      r'^(pt|por)(-|$)',
                      caseSensitive: false,
                    ).hasMatch(t.language ?? '') ||
                    RegExp(
                      'portugu',
                      caseSensitive: false,
                    ).hasMatch(t.title ?? ''),
              )
              .firstOrNull;
          if (preferred != null) {
            audioChosen = true;
            unawaited(player.setAudioTrack(preferred));
          }
        }
        if (mounted) setState(() {});
      }),
    );
    subscriptions.add(
      player.stream.completed.listen((completed) {
        if (completed && playback?.metadata['next_stream_id'] is String) {
          unawaited(openNext());
        }
      }),
    );
    progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(session.saveProgress()),
    );
    unawaited(open());
  }

  Future<void> open({String? streamId}) async {
    final current = ++revision;
    startup.reset();
    startup.start();
    firstFrameMs = null;
    mediaLoaded = false;
    setState(() {
      error = null;
      busy = true;
      audioChosen = false;
      quality = 'Automática';
    });
    try {
      final data = await session.open(streamId: streamId);
      if (!mounted || closing || current != revision) return;
      playback = data;
      await configureNativeEngine(player);
      await player.open(
        Media(data.url, httpHeaders: data.headers, start: data.position),
        play: true,
      );
      mediaLoaded = true;
      if (mounted && current == revision) setState(() => busy = false);
      scheduleHide();
    } catch (e) {
      if (mounted && !closing && current == revision) {
        setState(() {
          busy = false;
          error = e is ApiFailure
              ? '${e.message} (${e.code})'
              : 'Não foi possível iniciar o vídeo nativo.';
        });
      }
    }
  }

  Future<void> openNext() async {
    final id = playback?.metadata['next_stream_id'];
    if (id is String) await changeEpisode(id);
  }

  Future<void> changeEpisode(String id) async {
    if (busy || closing) return;
    setState(() {
      busy = true;
      status = 'Preparando o episódio…';
    });
    unawaited(session.saveProgress());
    try {
      await player.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Disposal also releases the native engine. */
    }
    if (mounted && !closing) await open(streamId: id);
  }

  Future<void> seek(Duration value) async {
    if (playback?.isLive == true) return;
    final duration = player.state.duration.inMilliseconds;
    if (duration <= 0) return;
    final target = Duration(
      milliseconds: value.inMilliseconds
          .clamp(0, duration > 0 ? duration : value.inMilliseconds)
          .toInt(),
    );
    session.position = target;
    unawaited(session.heartbeat(seek: true));
    await player.seek(target);
    scheduleHide();
  }

  void scheduleHide() {
    hideTimer?.cancel();
    if (player.state.playing) {
      hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !busy) setState(() => controls = false);
      });
    }
  }

  Future<void> leave() async {
    if (closing) return;
    setState(() => closing = true);
    revision++;
    session.scope.cancel();
    hideTimer?.cancel();
    unawaited(session.saveProgress());
    try {
      await player.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Disposal also releases the native engine. */
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    closing = true;
    revision++;
    hideTimer?.cancel();
    progressTimer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(session.close());
    unawaited(
      player.dispose().whenComplete(() => releaseNativeEngineAudio(player)),
    );
    super.dispose();
  }

  Future<void> chooseQuality() async {
    final p = playback;
    if (p == null || p.variants.isEmpty || busy) return;
    hideTimer?.cancel();
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Qualidade',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text('Automática'),
                onTap: () => Navigator.pop(context, {
                  'label': 'Automática',
                  'url': p.url,
                }),
              ),
              for (final item in p.variants)
                ListTile(
                  title: Text('${item['label']}'),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || closing) return;
    if (picked == null) {
      scheduleHide();
      return;
    }
    final u = Uri.tryParse('${picked['url']}');
    if (u == null || !session.acceptsMediaUri(u)) return;
    setState(() => busy = true);
    final position = player.state.position;
    try {
      session.position = position;
      final prepared = await session.prepareQuality(u.toString());
      await player.open(
        Media(
          prepared.toString(),
          httpHeaders: widget.api.mediaHeaders(prepared),
          start: position,
        ),
        play: true,
      );
      if (mounted) setState(() => quality = '${picked['label']}');
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível mudar a qualidade.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
      scheduleHide();
    }
  }

  Future<void> chooseAudio() async {
    hideTimer?.cancel();
    final tracks = player.state.tracks.audio
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();
    final track = await showModalBottomSheet<AudioTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Áudio')),
            for (final t in tracks)
              ListTile(
                title: Text(t.title ?? t.language ?? 'Áudio ${t.id}'),
                selected: t.id == player.state.track.audio.id,
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (track != null) {
      audioChosen = true;
      await player.setAudioTrack(track);
    }
    scheduleHide();
  }

  Future<void> chooseSubtitle() async {
    hideTimer?.cancel();
    final tracks = player.state.tracks.subtitle
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();
    final track = await showModalBottomSheet<SubtitleTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Legendas')),
            ListTile(
              title: const Text('Desativadas'),
              onTap: () => Navigator.pop(context, SubtitleTrack.no()),
            ),
            for (final t in tracks)
              ListTile(
                title: Text(t.title ?? t.language ?? 'Legenda ${t.id}'),
                selected: t.id == player.state.track.subtitle.id,
                onTap: () => Navigator.pop(context, t),
              ),
            for (final t in jsonRows(
              jsonMap(playback?.metadata['stream'])['subtitles'],
            ))
              if (t['content'] is String)
                ListTile(
                  title: Text('${t['label'] ?? t['language_code']}'),
                  onTap: () => Navigator.pop(
                    context,
                    SubtitleTrack.data(
                      t['content'] as String,
                      title: '${t['label'] ?? 'Legenda'}',
                      language: '${t['language_code'] ?? 'pt'}',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (track != null) await player.setSubtitleTrack(track);
    scheduleHide();
  }

  Future<void> chooseEpisode() async {
    if (session.seasons.isEmpty || busy) return;
    hideTimer?.cancel();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Episódios')),
              for (final season in session.seasons) ...[
                ListTile(title: Text('Temporada ${season['season_number']}')),
                for (final ep in jsonRows(season['episodes']))
                  if (selectSource(widget.source, jsonRows(ep['streams'])) !=
                      null)
                    ListTile(
                      title: Text('${ep['episode_number']} · ${ep['name']}'),
                      onTap: () => Navigator.pop(
                        context,
                        '${selectSource(widget.source, jsonRows(ep['streams']))!['id']}',
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
    if (id != null && mounted) {
      await changeEpisode(id);
    }
    if (mounted && !closing) scheduleHide();
  }

  static String time(Duration duration) {
    final s = duration.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = player.state,
        landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final total = state.duration.inMilliseconds.toDouble(),
        position = dragging ?? state.position.inMilliseconds.toDouble();
    final introEnd = (playback?.metadata['intro_end_seconds'] as num?)
        ?.toDouble();
    final introStart =
        (playback?.metadata['intro_start_seconds'] as num?)?.toDouble() ?? 0;
    return PopScope(
      canPop: closing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !landscape,
          bottom: !landscape,
          child: Column(
            children: [
              if (!landscape)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('player-back'),
                        tooltip: 'Voltar',
                        onPressed: leave,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          playback?.name ?? widget.source.example,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Text(
                        'NATIVO',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => controls = !controls);
                    if (controls) scheduleHide();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        key: const Key('native-video'),
                        controller: controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                      if (controls || busy || error != null)
                        Container(color: Colors.black38),
                      if (busy || state.buffering && error == null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  busy ? status : 'Carregando vídeo…',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 32),
                                const SizedBox(height: 12),
                                Text(error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => open(
                                    streamId: session.seasons.isNotEmpty
                                        ? session.activeStreamId
                                        : null,
                                  ),
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (landscape && controls)
                        Positioned(
                          top: 0,
                          left: 4,
                          right: 8,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Voltar',
                                onPressed: leave,
                                icon: const Icon(Icons.arrow_back),
                              ),
                              Expanded(
                                child: Text(
                                  playback?.name ?? widget.source.example,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (controls && !busy && error == null)
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (playback?.isLive != true)
                                IconButton(
                                  key: const Key('seek-back'),
                                  tooltip: 'Voltar 10 segundos',
                                  iconSize: 32,
                                  onPressed: () => seek(
                                    state.position -
                                        const Duration(seconds: 10),
                                  ),
                                  icon: const Icon(Icons.replay_10),
                                ),
                              const SizedBox(width: 24),
                              IconButton(
                                key: const Key('play-pause'),
                                tooltip: state.playing
                                    ? 'Pausar'
                                    : 'Reproduzir',
                                iconSize: 52,
                                onPressed: () async {
                                  await player.playOrPause();
                                  scheduleHide();
                                },
                                icon: Icon(
                                  state.playing
                                      ? Icons.pause_circle
                                      : Icons.play_circle,
                                ),
                              ),
                              const SizedBox(width: 24),
                              if (playback?.isLive != true)
                                IconButton(
                                  key: const Key('seek-forward'),
                                  tooltip: 'Avançar 10 segundos',
                                  iconSize: 32,
                                  onPressed: () => seek(
                                    state.position +
                                        const Duration(seconds: 10),
                                  ),
                                  icon: const Icon(Icons.forward_10),
                                ),
                            ],
                          ),
                        ),
                      if (controls && !busy && error == null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 4,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (playback?.isLive != true && total > 0)
                                Row(
                                  children: [
                                    Text(
                                      time(state.position),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        key: const Key('player-seek'),
                                        min: 0,
                                        max: total,
                                        value: position.clamp(0, total),
                                        onChangeStart: (v) {
                                          hideTimer?.cancel();
                                          setState(() => dragging = v);
                                        },
                                        onChanged: (v) =>
                                            setState(() => dragging = v),
                                        onChangeEnd: (v) {
                                          setState(() => dragging = null);
                                          unawaited(
                                            seek(
                                              Duration(milliseconds: v.toInt()),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Text(
                                      time(state.duration),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    key: const Key('player-audio'),
                                    tooltip: 'Áudio',
                                    onPressed: chooseAudio,
                                    icon: const Icon(
                                      Icons.headphones,
                                      size: 22,
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('player-subtitles'),
                                    tooltip: 'Legendas',
                                    onPressed: chooseSubtitle,
                                    icon: const Icon(
                                      Icons.subtitles_outlined,
                                      size: 22,
                                    ),
                                  ),
                                  if (playback?.variants.isNotEmpty == true)
                                    TextButton(
                                      key: const Key('player-quality'),
                                      onPressed: chooseQuality,
                                      child: Text(
                                        quality,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  if (session.seasons.isNotEmpty)
                                    IconButton(
                                      key: const Key('player-episodes'),
                                      tooltip: 'Episódios',
                                      onPressed: chooseEpisode,
                                      icon: const Icon(
                                        Icons.playlist_play,
                                        size: 24,
                                      ),
                                    ),
                                  if (playback?.metadata['next_stream_id']
                                      is String)
                                    IconButton(
                                      key: const Key('player-next'),
                                      tooltip: 'Próximo episódio',
                                      onPressed: openNext,
                                      icon: const Icon(Icons.skip_next),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (introEnd != null &&
                          state.position.inMilliseconds / 1000 >= introStart &&
                          state.position.inMilliseconds / 1000 < introEnd)
                        Positioned(
                          right: 16,
                          bottom: controls ? 110 : 20,
                          child: FilledButton(
                            onPressed: () => seek(
                              Duration(milliseconds: (introEnd * 1000).round()),
                            ),
                            child: const Text('Pular abertura'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!landscape)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.source.name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                      Text(
                        state.width != null
                            ? '${state.width} × ${state.height}'
                            : '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
