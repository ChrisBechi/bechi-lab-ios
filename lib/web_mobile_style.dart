import 'package:flutter/widgets.dart';

// Logical pixels mirror the responsive CSS values in apps/web/src/app/web.css.
class MobileLayout {
  MobileLayout(BuildContext context) : width = MediaQuery.sizeOf(context).width;
  final double width;
  static const background = Color(0xff0c1015);
  double get gutter => (width * .036).clamp(12.0, 24.0);
  double get artHeight => (width * .55).clamp(210.0, 400.0);
  double get artCopy => (width * .40).clamp(145.0, 286.0);
  double get coverWidth => (width * .26).clamp(92.0, 150.0);
  double get previewWidth => (width * .46).clamp(140.0, 240.0);
  double get headline => (width * .066).clamp(24.0, 34.0);
  double get railTitle => (width * .04).clamp(15.0, 18.0);
  int get columns => width <= 359
      ? 2
      : width <= 1000
      ? 3
      : (width / 180).floor();
  TextStyle get heading => TextStyle(
    fontSize: headline,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -headline * .03,
  );
  static const cardLabel = TextStyle(
    fontSize: 11,
    height: 1.28,
    fontWeight: FontWeight.w600,
    color: Color(0xffd8e2ee),
  );
}

class MobileBrand extends StatelessWidget {
  const MobileBrand({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 42,
    child: ClipRect(
      child: OverflowBox(
        minWidth: 66,
        maxWidth: 66,
        child: Image.asset(
          'assets/bechi-flix.webp',
          width: 66,
          semanticLabel: 'Bechi Flix',
        ),
      ),
    ),
  );
}
