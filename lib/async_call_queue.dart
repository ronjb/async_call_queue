// Copyright (c) 2021 Ron Booth. All rights reserved.
// Use of this source code is governed by a license that can be found in the
// LICENSE file.

library async_call_queue;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart' as synchronized;

/// AsyncCallQueue provides a queuing mechanism to prevent concurrent access
/// to asynchronous code via the `queueCall` method, and provides a way to
/// delay execute code via the `delayCall` method.
///
/// It also provides a way to know if subsequent calls are waiting to execute,
/// which allows the currently executing call to, for example, cancel doing
/// some work and return sooner.
///
/// The `dispose` method should be called when the AsyncCallQueue object is
/// no longer needed.
class AsyncCallQueue {
  AsyncCallQueue({this.debugMode = false});

  final bool debugMode;

  /// Calls the [func] immediately, unless a previous call to an async func is
  /// still executing (i.e. awaiting an async result), in which case it waits
  /// for the previous call to finish before calling the given [func].
  ///
  /// When the [func] eventually finishes executing, the result is returned.
  Future<T> queueCall<T>(
    FutureOr<T> Function(AsyncCallQueue queue, int callId) func, {
    Duration? timeout,
  }) {
    _prepareForNewCall();

    if (debugMode && _lock.inLock) {
      print('AsyncCallQueue: Waiting for previous call(s) to finish '
          'before calling $_latestCallId');
    }

    return _lock.synchronized<T>(() {
      return func(this, latestCallId);
    }, timeout: timeout);
  }

  /// Calls the [func] after the [delay]. If another call comes in before
  /// the delay finishes, the call is cancelled and the delay is restarted.
  ///
  /// If [preventConcurrentAccess] is true (the default), and another call
  /// comes in while the [func] being executed, but is awaiting an async
  /// result, the new call is not executed until the [func] finishes.
  ///
  void delayCall(
    FutureOr<dynamic> Function(AsyncCallQueue queue, int callId) func, {
    Duration delay = const Duration(seconds: 1),
    bool preventConcurrentAccess = true,
  }) {
    _prepareForNewCall();

    final noDelay = (delay.inMicroseconds <= 0);

    if (noDelay) {
      _call(
        func,
        delay: delay,
        preventConcurrentAccess: preventConcurrentAccess,
      );
    } else {
      _syncSubscription = Future<void>.delayed(delay).asStream().listen(
        (_) {
          _call(
            func,
            delay: delay,
            preventConcurrentAccess: preventConcurrentAccess,
          );
        },
        cancelOnError: true,
      );
    }
  }

  /// Every call is given a unique ID; this returns the most recent call's ID.
  int get latestCallId => _latestCallId;
  var _latestCallId = 0;

  /// Returns true if one or more calls have been made after the call with the
  /// given `callId`. Useful, for example, if you want to cancel doing some
  /// work in an async function if subsequent calls are waiting to execute.
  bool hasCallsWaitingAfter(int callId) => callId != _latestCallId;

  /// Call the [dispose] function when this object is no longer needed. It will
  /// cancel any pending delayed call. The [dispose] function must only be
  /// called once.
  @mustCallSuper
  void dispose() {
    assert(_disposed == false);
    _disposed = true;
    _syncSubscription?.cancel();
    _syncSubscription = null;
  }

  //
  // PRIVATE CODE
  //

  StreamSubscription? _syncSubscription;
  final _lock = synchronized.Lock();
  var _disposed = false;

  void _prepareForNewCall() {
    _latestCallId = _latestCallId.safeIncrement();

    if (debugMode && _syncSubscription != null) {
      print('AsyncCallQueue: Canceled previous call '
          'for new call $_latestCallId');
    }

    // Cancel any pending sync subscription.
    _syncSubscription?.cancel();
    _syncSubscription = null;
  }

  void _call(
    FutureOr<dynamic> Function(AsyncCallQueue queue, int callId) func, {
    required Duration delay,
    required bool preventConcurrentAccess,
  }) {
    if (_disposed) return;

    final noDelay = (delay.inMicroseconds <= 0);

    if (!noDelay && preventConcurrentAccess && _lock.locked) {
      if (debugMode) {
        print('AsyncCallQueue: In call, so trying again in $delay');
      }
      // Try again after delay...
      delayCall(func, delay: delay);
    } else {
      if (preventConcurrentAccess) {
        _lock.synchronized<void>(
          () async {
            await func(this, latestCallId);
          },
        );
      } else {
        func(this, latestCallId);
      }
    }
  }
}

// "On the web, integer values are represented as JavaScript numbers
// (64-bit floating-point values with no fractional part) and can be
// from -2^53 to 2^53 - 1."
//
// Quote from: https://dart.dev/guides/language/language-tour#numbers

/// 2^53 - 1, the maximum safe integer value for dart code that might be
/// compiled to javascript (i.e. used in a web app).
const kMaxJsInt = 0x1FFFFFFFFFFFFF; // 2^53 - 1

/// -2^53, the minimum safe integer value for dart code that might be
/// compiled to javascript (i.e. used in a web app).
const kMinJsInt = -0x20000000000000; // -2^53

extension AsyncCallQueueExtOnInt on int {
  /// Returns ```this == kMaxJsInt ? wrapTo : this + 1```
  int safeIncrement({int wrapTo = kMinJsInt}) =>
      (this == kMaxJsInt ? wrapTo : this + 1);
}
