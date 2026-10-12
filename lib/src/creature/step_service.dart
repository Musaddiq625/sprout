import 'dart:async';

import 'package:flutter/services.dart';

/// Wraps the Android TYPE_STEP_DETECTOR sensor via a local
/// EventChannel — emits one event per detected step. Errors on
/// platforms without the channel/sensor or when the
/// ACTIVITY_RECOGNITION permission is denied — callers ignore it
/// and walking simply never triggers.
class StepService {
  StepService._();

  static const _eventChannel =
      EventChannel('com.sprout.musaddiq625/step_stream');

  /// One event per detected step.
  static Stream<int> get steps =>
      _eventChannel.receiveBroadcastStream().where((e) => e == 1)
          .map((_) => 1);
}
