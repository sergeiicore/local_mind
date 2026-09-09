import 'package:flutter/services.dart';

class NativeService {
  static const channel = MethodChannel('local_mind/native');
  Future<T?> call<T>(String method, [Map<String, dynamic>? args]) =>
      channel.invokeMethod<T>(method, args);
  Future<String?> secret(String key) => call<String>('getSecret', {'key': key});
  Future<void> setSecret(String key, String value) async =>
      call<void>('setSecret', {'key': key, 'value': value});
  Future<List<Map<String, dynamic>>> calendars() async =>
      (await channel.invokeListMethod<dynamic>('calendars') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<List<Map<String, dynamic>>> today() async =>
      (await channel.invokeListMethod<dynamic>('today') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
