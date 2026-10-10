import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/app_log_config.dart';
import 'package:quark/utils/app_log_sink_io.dart';
import 'package:quark/utils/app_log_sink_web.dart';

void main() {
  late Directory root;

  File current() => File('${root.path}/${AppLogConfig.fileName}');
  File rotated() => File('${current().path}.1');

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('app_log');
    // The sink creates its directory itself; start without one.
    root = Directory('${temp.path}/${AppLogConfig.directoryName}');
    addTearDown(() => temp.delete(recursive: true));
  });

  test('entries are appended and survive a relaunch', () async {
    final first = IoAppLogSink(root: () async => root)
      ..write('one\n')
      ..write('two\n');
    // Reading waits behind the writes queued before it.
    expect(await first.read(), 'one\ntwo\n');
    // A second sink on the same directory is the next launch.
    final relaunched = IoAppLogSink(root: () async => root)..write('three\n');

    expect(await relaunched.read(), 'one\ntwo\nthree\n');
    expect(await current().readAsString(), 'one\ntwo\nthree\n');
  });

  test(
    'a full file is rotated out, and only one rotated file is kept',
    () async {
      final sink = IoAppLogSink(root: () async => root, maxFileBytes: 10);

      sink
        ..write('aaaa\n')
        ..write('bbbb\n')
        ..write('cccc\n');
      expect(await sink.read(), 'aaaa\nbbbb\ncccc\n');
      expect(await rotated().readAsString(), 'aaaa\nbbbb\n');
      expect(await current().readAsString(), 'cccc\n');

      sink
        ..write('dddd\n')
        ..write('eeee\n');
      // The oldest file is gone: the log holds at most two files' worth.
      expect(await sink.read(), 'cccc\ndddd\neeee\n');
      expect(await root.list().length, 2);
    },
  );

  test('rotation counts what an earlier launch left behind', () async {
    await root.create(recursive: true);
    await current().writeAsString('12345678\n');

    final sink = IoAppLogSink(root: () async => root, maxFileBytes: 10)
      ..write('next\n');

    expect(await sink.read(), '12345678\nnext\n');
    expect(await rotated().readAsString(), '12345678\n');
  });

  test(
    'a directory that cannot be resolved keeps nothing and does not throw',
    () async {
      final sink = IoAppLogSink(root: () async => throw StateError('no disk'))
        ..write('lost\n');

      expect(await sink.read(), '');
    },
  );

  test('nothing written reads as empty', () async {
    expect(await IoAppLogSink(root: () async => root).read(), '');
  });

  test('the web sink keeps nothing', () async {
    const sink = NoAppLogSink();
    sink.write('dropped\n');

    expect(sink.persists, isFalse);
    expect(await sink.read(), '');
  });
}
