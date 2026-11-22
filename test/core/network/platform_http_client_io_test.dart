import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meal_client/core/network/platform_http_client_io.dart';

void main() {
  test('ETag를 그대로 조건부 헤더에 넣고 304를 빈 본문으로 반환한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['If-None-Match'], '"menu-v2"');
      expect(request.headers.containsKey('If-Modified-Since'), isFalse);
      return http.Response('', 304);
    });
    addTearDown(client.close);

    final response = await fetchPlatformRawConditional(
      client,
      'https://example.com/v2/menu',
      ifNoneMatch: '"menu-v2"',
    );

    expect(response, (statusCode: 304, body: null));
  });
}
