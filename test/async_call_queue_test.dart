import 'dart:async';

import 'package:test/test.dart';

import 'package:async_call_queue/async_call_queue.dart';

const oneMillisecond = Duration(milliseconds: 1);
const twoMilliseconds = Duration(milliseconds: 2);
const fiveMilliseconds = Duration(milliseconds: 5);

void main() {
  test('compiles with no errors', () {
    final acq = AsyncCallQueue();
    expect(acq.latestCallId, 0);
  });

  test('test queueCall', () async {
    // This is the control. The delayedWrite1234To function writes each
    // number in the array [1, 2, 3, 4] to the string buffer with a
    // millisecond delay before each write. Calling it two times in a row
    // should result in '11223344'.
    var buff = StringBuffer();
    var f1 = delayedWrite1234To(buff);
    var f2 = delayedWrite1234To(buff);
    await Future.wait<void>([f1, f2]);
    expect(buff.toString(), '11223344');

    // This verifies that `queueCall` synchronizes the calls to
    // delayedWrite1234To so that the first call finishes before the
    // second call is executed, resulting in '12341234'.
    var acq = AsyncCallQueue();
    buff = StringBuffer();
    f1 = acq.queueCall<void>((acq, callId) => delayedWrite1234To(buff));
    f2 = acq.queueCall<void>((acq, callId) => delayedWrite1234To(buff));
    await Future.wait<void>([f1, f2]);
    acq.dispose();
    expect(buff.toString(), '12341234');

    // This verifies that the first call can cancel some of its work when
    // the next call starts waiting. We delay the second call by two
    // milliseconds, so the result should be '121234'
    acq = AsyncCallQueue();
    buff = StringBuffer();
    buff = StringBuffer();
    f1 = acq.queueCall<void>((acq, callId) async {
      for (final value in [1, 2, 3, 4]) {
        await delayedWriteTo(buff, value);
        if (acq.hasCallsWaitingAfter(callId)) return;
      }
    });
    await Future<void>.delayed(twoMilliseconds);
    f2 = acq.queueCall<void>((acq, callId) => delayedWrite1234To(buff));
    await Future.wait<void>([f1, f2]);
    acq.dispose();
    expect(buff.toString(), '121234');
  });

  test('test delayCall', () async {
    // In this example, only the last call should complete because
    // we're making a new call every millisecond and the delay is
    // 5 milliseconds.
    final buff = StringBuffer();
    final acq = AsyncCallQueue();
    final completer = Completer<void>();
    for (var c = 0; c < 10; c++) {
      await Future<void>.delayed(oneMillisecond);
      acq.delayCall((acq, callId) {
        buff.write(callId);
        completer.complete();
      }, delay: fiveMilliseconds);
    }
    await completer.future;
    acq.dispose();
    expect(buff.toString(), '10');
  });
}

/// Writes the [value] to the [buff] after the [delay].
Future delayedWriteTo(
  StringBuffer buff,
  int value, {
  Duration delay = oneMillisecond,
}) async {
  await Future<void>.delayed(delay);
  buff.write(value);
}

/// Writes the values 1, 2, 3, 4 to the [buff] with a [delay] before each
/// number is written.
Future delayedWrite1234To(
  StringBuffer buff, {
  Duration delay = oneMillisecond,
}) async {
  for (final value in [1, 2, 3, 4]) {
    await delayedWriteTo(buff, value, delay: delay);
  }
}
