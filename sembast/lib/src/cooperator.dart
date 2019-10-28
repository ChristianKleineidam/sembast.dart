import 'dart:async';

/// Simple cooperate that checks every 4ms
class Cooperator {
  /// True if activated.
  final bool cooperateOn = true;

  /// Timer.
  var cooperateStopWatch = Stopwatch()..start();

  /// Need to cooperate every 16 milliseconds.
  bool get needCooperate =>
      cooperateOn && cooperateStopWatch.elapsedMilliseconds > 4;

  /// Cooperate if needed.
  FutureOr cooperate() {
    if (needCooperate) {
      cooperateStopWatch
        ..stop()
        ..reset()
        ..start();
      // Just don't make it 0, tested for best performance using Flutter
      // on a (non-recent) Nexus 5
      return Future.delayed(const Duration(microseconds: 100));
    } else {
      return null;
    }
    // await Future.value();
    //print('breath');
  }
}
