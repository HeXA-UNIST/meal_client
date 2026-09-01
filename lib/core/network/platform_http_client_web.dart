import 'package:http/http.dart';

Exception createHttpException(int statusCode) =>
    Exception("HTTP $statusCode: Response Error");

// 웹에서는 package:http의 기본 Client()가
// 브라우저 환경에 맞는 구현을 자동으로 선택한다.
Client createPlatformHttpClient() => Client();
