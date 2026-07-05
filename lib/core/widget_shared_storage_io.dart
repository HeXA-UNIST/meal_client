import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _sharedStorageChannel = MethodChannel(
  'pro.hexa.meal.meal_client/widget_shared_storage',
);

Future<Directory> sharedWidgetCacheDir() async {
  if (Platform.isAndroid ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isWindows) {
    return getApplicationSupportDirectory();
  }

  if (Platform.isIOS) {
    final path = await _sharedStorageChannel.invokeMethod<String>(
      'sharedWidgetCacheDir',
    );
    if (path == null || path.isEmpty) {
      throw StateError('iOS shared widget cache directory is not available');
    }
    return Directory(path);
  }

  throw UnsupportedError('This platform does not support shared widget cache');
}

Future<void> saveSharedWidgetFileAsString(String fileName, String data) async {
  final dir = await sharedWidgetCacheDir();
  await dir.create(recursive: true);
  final file = File('${dir.path}/$fileName');
  final tmpFile = File(
    '${dir.path}/$fileName.tmp.${DateTime.now().microsecondsSinceEpoch}',
  );

  await tmpFile.writeAsString(data, flush: true);
  try {
    await tmpFile.rename(file.path);
  } on FileSystemException {
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }
}

Future<String> readSharedWidgetFileAsString(String fileName) async {
  final dir = await sharedWidgetCacheDir();
  final file = File('${dir.path}/$fileName');
  return file.readAsString();
}

Future<DateTime> getLastModifiedOfSharedWidgetFile(String fileName) async {
  final dir = await sharedWidgetCacheDir();
  final file = File('${dir.path}/$fileName');
  return file.lastModified();
}
