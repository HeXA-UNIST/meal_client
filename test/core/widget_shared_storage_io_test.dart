import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/widget_shared_storage_io.dart';

void main() {
  test('파일 marker lock은 isolate 간 경합을 직렬화한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bapu-widget-lock-',
    );
    final marker = File('${directory.path}/meal-next.json.lock.$pid');
    try {
      final first = Isolate.run(() => _holdLock(directory.path));
      await _waitUntil(marker.exists);

      var firstFinished = false;
      unawaited(first.whenComplete(() => firstFinished = true));
      var enteredAfterFirst = false;
      await withSharedWidgetFileLock(
        'meal-next.json',
        () async => enteredAfterFirst = firstFinished,
        directory: directory,
      );
      await first;

      expect(enteredAfterFirst, isTrue);
      expect(marker.existsSync(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('같은 PID의 고아 marker는 제한 시간 뒤 action을 건너뛴다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bapu-widget-orphan-',
    );
    final marker = File('${directory.path}/meal-next.json.lock.$pid');
    try {
      await marker.writeAsString('orphan');
      var entered = false;

      await expectLater(
        withSharedWidgetFileLock(
          'meal-next.json',
          () async => entered = true,
          directory: directory,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(entered, isFalse);
      expect(marker.existsSync(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('다른 PID의 고아 marker는 현재 PID의 action을 막지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bapu-widget-foreign-',
    );
    final foreignMarker = File(
      '${directory.path}/meal-next.json.lock.${pid + 1}',
    );
    try {
      await foreignMarker.writeAsString('orphan');
      var entered = false;

      await withSharedWidgetFileLock(
        'meal-next.json',
        () async => entered = true,
        directory: directory,
      );

      expect(entered, isTrue);
      expect(foreignMarker.existsSync(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _holdLock(String directoryPath) {
  return withSharedWidgetFileLock(
    'meal-next.json',
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
    directory: Directory(directoryPath),
  );
}

Future<void> _waitUntil(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('lock marker was not created');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
