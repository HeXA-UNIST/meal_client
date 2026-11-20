import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/menu_header_region.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('잘못된 좌표와 채널 오류 후에도 같은 구독에서 새 영역을 받는다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = EventChannel(
      'pro.hexa.meal.meal_client/menu_header_regions',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (height, sink) {
          expect(height, 52);
          sink.success([669, 951, 82, 14, 20, 500, 52]);
          sink.success([669, 951]);
          sink.success([669, 951, 82, 14, double.nan, 500, 52]);
          sink.error(code: 'HEADER_UNAVAILABLE');
          sink.success([669, 951, 82, 14, 20, 480.5, 52]);
          sink.endOfStream();
        },
      ),
    );
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    final widths = await MenuHeaderRegion.observe()
        .map((event) => event?.frame.width)
        .toList();
    expect(widths, [500, null, null, null, 480.5]);
  }, skip: kIsWeb); // 웹에서는 iOS 채널을 구독하지 않는다.
}
