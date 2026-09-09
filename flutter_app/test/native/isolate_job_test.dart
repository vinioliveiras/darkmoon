import 'dart:isolate';

import 'package:darkmoon/native/isolate_job.dart';
import 'package:flutter_test/flutter_test.dart';

// A worker that throws before ever sending a result — the shape of every
// hang the app used to have (missing model, corrupt file, ORT refusing to
// load). Top-level so Isolate.spawn can take it.
void _throwingEntry(SendPort port) {
  throw StateError('model missing');
}

// A worker that polls a shared cancel flag and reports when it sees it,
// standing in for the tile loop of the AI isolates.
void _pollingEntry(List<Object> args) async {
  final port = args[0] as SendPort;
  final flag = IsolateCancelFlag.fromAddress(args[1] as int);
  for (var i = 0; i < 1000; i++) {
    if (flag.isSet) {
      port.send('cancelled after $i polls');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  port.send('never saw the flag');
}

void main() {
  group('IsolateError.of', () {
    test('recognises the two-string list onError delivers', () {
      final error = IsolateError.of(['Bad state: x', '#0 main']);
      expect(error, isNotNull);
      expect(error!.error, 'Bad state: x');
      expect(error.stackTrace, '#0 main');
      expect(error.trace, isA<StackTrace>());
    });

    test('leaves every other message alone', () {
      expect(IsolateError.of(null), isNull);
      expect(IsolateError.of('a string'), isNull);
      expect(IsolateError.of(['one']), isNull);
      expect(IsolateError.of([1, 2]), isNull);
      expect(IsolateError.of(['a', 'b', 'c']), isNull);
    });
  });

  test(
    'a worker that throws before replying reaches the caller as an '
    'IsolateError instead of hanging it (onError wired to the same port)',
    () async {
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _throwingEntry,
        receivePort.sendPort,
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
      );
      final first = await receivePort.first.timeout(const Duration(seconds: 5));
      receivePort.close();
      final error = IsolateError.of(first);
      expect(error, isNotNull);
      expect(error!.error, contains('model missing'));
    },
  );

  group('IsolateCancelFlag', () {
    test('starts clear, set is sticky, dispose makes it read clear', () {
      final flag = IsolateCancelFlag();
      expect(flag.isSet, isFalse);
      flag.set();
      expect(flag.isSet, isTrue);
      flag.set();
      expect(flag.isSet, isTrue);
      flag.dispose();
      expect(flag.isSet, isFalse);
      // Neither of these may touch freed memory.
      flag.set();
      flag.dispose();
    });

    test(
      'a view from the address sees the owner set it, and cannot free it',
      () {
        final owner = IsolateCancelFlag();
        final view = IsolateCancelFlag.fromAddress(owner.address);
        expect(view.isSet, isFalse);
        owner.set();
        expect(view.isSet, isTrue);
        view.dispose();
        // The owner still owns live memory after the view's no-op dispose.
        expect(owner.isSet, isTrue);
        owner.dispose();
      },
    );

    test('crosses the isolate boundary without a message', () async {
      final receivePort = ReceivePort();
      final exitPort = ReceivePort();
      final flag = IsolateCancelFlag();
      await Isolate.spawn(_pollingEntry, <Object>[
        receivePort.sendPort,
        flag.address,
      ], onExit: exitPort.sendPort);
      final exited = disposeOnIsolateExit(exitPort, flag);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      flag.set();
      final reply = await receivePort.first.timeout(const Duration(seconds: 5));
      receivePort.close();
      expect(reply, startsWith('cancelled after'));
      await exited.timeout(const Duration(seconds: 5));
    });
  });
}
