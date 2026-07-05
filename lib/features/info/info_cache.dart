import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/widget_shared_storage.dart';

typedef InfoCacheWriter = Future<void> Function(String fileName, String data);
typedef InfoCacheReader = Future<String> Function(String fileName);
typedef InfoCacheLastModifiedReader =
    Future<DateTime> Function(String fileName);

class InfoCache {
  InfoCache({
    String fileName = StorageKeys.infoCacheFile,
    InfoCacheWriter? writeFile,
    InfoCacheReader? readFile,
    InfoCacheLastModifiedReader? readLastModified,
  }) : _fileName = fileName,
       _writeFile = writeFile ?? saveSharedWidgetFileAsString,
       _readFile = readFile ?? readSharedWidgetFileAsString,
       _readLastModified =
           readLastModified ?? getLastModifiedOfSharedWidgetFile;

  final String _fileName;
  final InfoCacheWriter _writeFile;
  final InfoCacheReader _readFile;
  final InfoCacheLastModifiedReader _readLastModified;

  Future<void> writeRawInfoJson(String rawJson) {
    return _writeFile(_fileName, rawJson);
  }

  Future<String> readRawInfoJson() {
    return _readFile(_fileName);
  }

  Future<DateTime> getRawInfoUpdatedAt() {
    return _readLastModified(_fileName);
  }
}
