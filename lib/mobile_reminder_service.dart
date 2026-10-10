import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MobileReminderService {
  MobileReminderService._();

  static const MethodChannel _channel =
      MethodChannel('com.ilevit/daily_note_reminder');

  static Future<void> initialize() async {}

  static Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  static Future<void> scheduleDaily({
    required int hour,
    required int minute,
  }) async {
    await _channel.invokeMethod<void>(
      'scheduleDaily',
      {'hour': hour, 'minute': minute},
    );
  }

  static Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancelDaily');
  }

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
