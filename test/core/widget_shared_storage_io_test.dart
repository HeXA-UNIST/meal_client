import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:meal_client/core/widget_shared_storage_io.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('공유 캐시 파일 저장', () {
    late Directory directory;
    const channel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('bapu-widget-save-');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => directory.path,
      );
    });

    tearDown(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });

    for (final cleanupFails in [false, true]) {
      test('교체 실패 시 기존 캐시와 원래 오류를 보존한다 (정리 실패: $cleanupFails)', () async {
        final file = File('${directory.path}/meal.json');
        final temporary = File('${directory.path}/meal.json.tmp.test');
        await file.writeAsString('old');
        final failure = FileSystemException('교체 실패', file.path);

        await expectLater(
          IOOverrides.runZoned(
            () => saveSharedWidgetFileAsString('meal.json', 'new'),
            createFile: (path) => path == file.path
                ? file
                : _RenameFailingFile(temporary, failure, cleanupFails),
          ),
          throwsA(same(failure)),
        );

        expect(await file.readAsString(), 'old');
        expect(await temporary.exists(), cleanupFails);
      });
    }
  });

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

// 실제 파일에 기록하되 교체와 정리 실패만 주입한다.
class _RenameFailingFile extends Fake implements File {
  _RenameFailingFile(this.file, this.failure, this.cleanupFails);

  final File file;
  final FileSystemException failure;
  final bool cleanupFails;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => file.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  Future<File> rename(String newPath) async => throw failure;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (cleanupFails) throw FileSystemException('임시 파일 정리 실패', file.path);
    return file.delete(recursive: recursive);
  }
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
