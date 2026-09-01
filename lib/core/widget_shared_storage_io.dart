import 'dart:async';
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

  throw UnsupportedError('이 플랫폼은 위젯 공유 캐시 디렉터리를 지원하지 않습니다');
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

  if (Platform.isIOS) {
    await _sharedStorageChannel.invokeMethod<void>(
      'excludeFileFromBackup',
      file.path,
    );
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

bool isMissingSharedWidgetFileError(Object error) =>
    error is FileSystemException && error.osError?.errorCode == 2;

/// 동일 PID의 foreground/Workmanager isolate가 같은 위젯 cache를 갱신할 때
/// compare-and-write 구간만 짧게 직렬화한다.
Future<T> withSharedWidgetFileLock<T>(
  String fileName,
  Future<T> Function() action, {
  Directory? directory,
}) async {
  final dir = directory ?? await sharedWidgetCacheDir();
  await dir.create(recursive: true);
  final lockFile = File('${dir.path}/$fileName.lock.$pid');
  final marker = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  var acquired = false;
  while (!acquired) {
    try {
      await lockFile.create(exclusive: true);
    } on FileSystemException {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for widget cache lock');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      continue;
    }

    try {
      await lockFile.writeAsString(marker, flush: true);
      acquired = true;
    } catch (_) {
      // create 성공 뒤 초기화가 실패한 marker는 이 호출만 소유하므로,
      // 다음 대기자가 고아 marker에 막히지 않게 즉시 회수한다.
      try {
        await lockFile.delete();
      } on FileSystemException {
        // marker가 이미 사라졌다면 다른 정리 경로가 처리한 것이다.
      }
      rethrow;
    }
  }
  try {
    return await action();
  } finally {
    try {
      if (await lockFile.readAsString() == marker) {
        await lockFile.delete();
      }
    } on FileSystemException {
      // 비정상 종료 뒤 이미 사라진 경우다.
    }
  }
}

bool get supportsSharedWidgetCache => true;
