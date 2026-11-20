import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MenuHeaderRegion {
  const MenuHeaderRegion(this.size, this.topInset, this.frame);

  final Size size;
  final double topInset;
  final Rect frame;

  static Stream<MenuHeaderRegion?> observe() async* {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    const channel = EventChannel(
      'pro.hexa.meal.meal_client/menu_header_regions',
    );
    await for (final event in channel.receiveBroadcastStream(toolbarHeight)) {
      final values = (event as List).cast<double>();
      yield values.isEmpty
          ? null
          : MenuHeaderRegion(
              Size(values[0], values[1]),
              values[2],
              Rect.fromLTWH(values[3], values[4], values[5], values[6]),
            );
    }
  }

  bool fits(MediaQueryData media) {
    // 회전 직후 이전 창의 좌표가 새 화면에 한 프레임이라도 적용되지 않게 한다.
    final tolerance = 1 / media.devicePixelRatio;
    return (media.size.width - size.width).abs() <= tolerance &&
        (media.size.height - size.height).abs() <= tolerance &&
        (media.padding.top - topInset).abs() <= tolerance &&
        media.padding.left == 0 &&
        media.padding.right == 0 &&
        frame.height >= toolbarHeight &&
        frame.width >= 56 + 140 + media.textScaler.scale(120) &&
        rowHeight < topInset + toolbarHeight;
  }

  static const toolbarHeight = 52.0;
  double get toolbarTop => frame.center.dy - toolbarHeight / 2;
  double get rowHeight => math.max(topInset, frame.bottom);
}
