import 'dart:async';
import 'package:flutter/services.dart';

class TrueHeadingService {
  static const _channel = EventChannel('with_light_star/true_heading');

  static Stream<dynamic> get headingStream => _channel.receiveBroadcastStream();
}
