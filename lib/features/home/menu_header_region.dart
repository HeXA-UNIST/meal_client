import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MenuHeaderRegion {
  const MenuHeaderRegion(this.size, this.topInset, this.frame);

  final Size size;
  final double topInset;
  final Rect frame;

  static Stream<MenuHeaderRegion?> observe() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream.empty();
    }
    const channel = EventChannel(
      'pro.hexa.meal.meal_client/menu_header_regions',
    );
    return channel
        .receiveBroadcastStream(toolbarHeight)
        .transform(
          StreamTransformer<dynamic, MenuHeaderRegion?>.fromHandlers(
            handleData: (event, sink) => sink.add(_decode(event)),
            handleError: (error, stack, sink) => sink.add(null),
          ),
        );
  }

  static MenuHeaderRegion? _decode(Object? event) {
    if (event case [
      num w,
      num h,
      num inset,
      num x,
      num y,
      num width,
      num height,
    ]) {
      final size = Size(w.toDouble(), h.toDouble());
      final frame = Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );
      if (size.isFinite &&
          !size.isEmpty &&
          inset.isFinite &&
          inset >= 0 &&
          frame.isFinite &&
          !frame.isEmpty &&
          frame.left >= 0 &&
          frame.top >= 0 &&
          frame.right <= size.width &&
          frame.bottom <= size.height) {
        return MenuHeaderRegion(size, inset.toDouble(), frame);
      }
    }
    return null;
  }

  bool fits(MediaQueryData media) {
    // 회전 직후 이전 창의 좌표가 새 화면에 한 프레임이라도 적용되지 않게 한다.
    final tolerance = 1 / media.devicePixelRatio;
    return (media.size.width - size.width).abs() <= tolerance &&
        (media.size.height - size.height).abs() <= tolerance &&
        (media.padding.top - topInset).abs() <= tolerance &&
        media.padding.left == 0 &&
        media.padding.right == 0 &&
        frame.height + tolerance + precisionErrorTolerance >= toolbarHeight &&
        // 기본 leading 폭, 끼니 버튼 영역, 글자 배율을 적용한 날짜 영역.
        frame.width >= 56 + 140 + media.textScaler.scale(120) &&
        rowHeight < topInset + toolbarHeight;
  }

  static const toolbarHeight = 52.0;
  double get fittedToolbarHeight => math.min(toolbarHeight, frame.height);
  double get toolbarTop => frame.top + (frame.height - fittedToolbarHeight) / 2;
  double get rowHeight => math.max(topInset, frame.bottom);
}
