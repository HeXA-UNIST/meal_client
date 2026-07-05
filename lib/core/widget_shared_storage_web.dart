Future<Never> sharedWidgetCacheDir() async {
  throw UnsupportedError('웹 플랫폼은 위젯 공유 캐시를 지원하지 않습니다');
}

Future<void> saveSharedWidgetFileAsString(String fileName, String data) async {}

Future<String> readSharedWidgetFileAsString(String fileName) async {
  throw UnsupportedError('웹 플랫폼은 위젯 공유 캐시를 지원하지 않습니다');
}

Future<DateTime> getLastModifiedOfSharedWidgetFile(String fileName) async {
  throw UnsupportedError('웹 플랫폼은 위젯 공유 캐시를 지원하지 않습니다');
}
