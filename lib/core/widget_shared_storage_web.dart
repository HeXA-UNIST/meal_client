Never _unsupportedOnWeb() =>
    throw UnsupportedError('Web does not support shared widget cache');

Future<Never> sharedWidgetCacheDir() async => _unsupportedOnWeb();

Future<void> saveSharedWidgetFileAsString(String fileName, String data) async {}

Future<String> readSharedWidgetFileAsString(String fileName) async =>
    _unsupportedOnWeb();

Future<DateTime> getLastModifiedOfSharedWidgetFile(String fileName) async =>
    _unsupportedOnWeb();
