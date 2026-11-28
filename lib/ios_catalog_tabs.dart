import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class IosCatalogTabs extends StatefulWidget {
  const IosCatalogTabs({
    super.key,
    required this.index,
    required this.labels,
    required this.onSelected,
  });
  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  static const viewType = 'app.bechiflix.native/catalog-tabs';

  static Future<bool> available() async {
    try {
      return await const MethodChannel(
            viewType,
          ).invokeMethod<bool>('available') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  State<IosCatalogTabs> createState() => _IosCatalogTabsState();
}

class _IosCatalogTabsState extends State<IosCatalogTabs> {
  MethodChannel? channel;
  void attach(int id) {
    if (!mounted) return;
    final bridge = MethodChannel('${IosCatalogTabs.viewType}/$id');
    channel = bridge;
    bridge.setMethodCallHandler((call) async {
      final value = call.arguments;
      if (mounted &&
          call.method == 'selected' &&
          value is int &&
          value >= 0 &&
          value < widget.labels.length &&
          value != widget.index) {
        widget.onSelected(value);
      }
    });
    unawaited(bridge.invokeMethod<void>('select', widget.index));
  }

  @override
  void didUpdateWidget(IosCatalogTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      unawaited(channel?.invokeMethod<void>('select', widget.index));
    }
  }

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: IosCatalogTabs.viewType,
    creationParamsCodec: const StandardMessageCodec(),
    creationParams: {'index': widget.index, 'labels': widget.labels},
    onPlatformViewCreated: attach,
    gestureRecognizers: {
      Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );
}
