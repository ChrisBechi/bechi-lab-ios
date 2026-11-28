import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ExpandableSynopsis extends StatefulWidget {
  const ExpandableSynopsis(this.text, {super.key, this.collapsedLines = 4});
  final String text;
  final int collapsedLines;
  @override
  State<ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<ExpandableSynopsis> {
  bool expanded = false;
  @override
  void didUpdateWidget(ExpandableSynopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = widget.collapsedLines;
        final measure = TextPainter(
          text: TextSpan(
            text: widget.text,
            style: DefaultTextStyle.of(context).style,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: lines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = measure.didExceedMaxLines;
        measure.dispose();
        if (!overflows) return Text(widget.text);
        final label = Text(expanded ? 'Ver menos…' : 'Ver mais…');
        void toggle() => setState(() => expanded = !expanded);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: expanded ? null : lines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            Semantics(
              expanded: expanded,
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: toggle,
                      child: label,
                    )
                  : TextButton(onPressed: toggle, child: label),
            ),
          ],
        );
      },
    );
  }
}
