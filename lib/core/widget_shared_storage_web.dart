Never _unsupportedOnWeb() =>
    throw UnsupportedError('웹 플랫폼은 위젯 공유 캐시를 지원하지 않습니다');

Future<Never> sharedWidgetCacheDir() async => _unsupportedOnWeb();

Future<void> saveSharedWidgetFileAsString(String fileName, String data) async {}

Future<String> readSharedWidgetFileAsString(String fileName) async =>
    _unsupportedOnWeb();

Future<DateTime> getLastModifiedOfSharedWidgetFile(String fileName) async =>
    _unsupportedOnWeb();

Future<T> withSharedWidgetFileLock<T>(
  String fileName,
  Future<T> Function() action, {
  Object? directory,
}) => action();

bool get supportsSharedWidgetCache => false;
