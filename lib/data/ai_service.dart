import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models.dart';
import 'native_service.dart';
import 'network_service.dart';

class AiResult {
  const AiResult(this.intent, this.profile, this.attempts);
  final Intent intent;
  final String profile;
  final List<String> attempts;
}

class AiService {
  AiService(this.network, this.native);
  final NetworkService network;
  final NativeService native;

  static Uri endpoint(AiProfile profile) {
    if (profile.isCodex) {
      throw const FormatException('Codex CLI не использует HTTP endpoint');
    }
    final uri = Uri.tryParse(profile.endpoint);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (!profile.isLocal && uri.scheme != 'https') ||
        (profile.isLocal && !['http', 'https'].contains(uri.scheme))) {
      throw const FormatException(
        'Используйте HTTPS; HTTP разрешён только для localhost',
      );
    }
    return uri.replace(
      path:
          '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/${profile.protocol == 'responses' ? 'responses' : 'chat/completions'}',
    );
  }

  static List<AiProfile> candidates(Settings settings) => settings.profiles
      .where(
        (p) =>
            p.enabled &&
            (!settings.localOnly || p.isLocal) &&
            (settings.selectedProfile == 'auto' ||
                settings.selectedProfile == p.id),
      )
      .toList();

  static const contract = '''Return ONLY a JSON object, no markdown fencing:
{"kind":"note|task|event|answer|clarification","text":"readable note, task title, event title, answer or question","start":null,"end":null,"question":null}
start/end: null or ISO8601 with explicit UTC offset. Never invent dates or duration.
Only one action is supported per request. If several actions are requested, ask which to do first.
For a reminder use task with start as its due time. For a calendar booking use event.
For missing required details use clarification. For a question use answer, using only supplied facts.
''';

  Future<AiResult> interpret({
    required Settings settings,
    required String input,
    required String rules,
    String context = '',
  }) async {
    final profiles = candidates(settings);
    if (profiles.isEmpty) {
      throw const FormatException(
        'Добавьте AI-профиль в настройках. Заметки и ручное создание работают без AI.',
      );
    }
    final attempts = <String>[];
    for (final profile in profiles) {
      try {
        final system =
            '$rules\n$contract\nCurrent local time: ${localStamp(DateTime.now())}. Time zone: ${DateTime.now().timeZoneName}.';
        final user = jsonEncode({
          'request': input,
          'explicitlyAttachedContext': context,
        });
        if (profile.isCodex) {
          final text = await native.call<String>('runCodex', {
            'model': profile.model,
            'prompt': '$system\n\n$user',
          });
          if (text == null || text.trim().isEmpty) {
            throw const ApiException('Codex не вернул ответ');
          }
          return AiResult(Intent.parse(text), profile.name, attempts);
        }

        final uri = endpoint(profile);
        final key = await native.secret('ai.${profile.id}');
        if (!profile.isLocal && (key == null || key.isEmpty)) {
          throw const ApiException('У профиля нет API-ключа', status: 401);
        }
        final dynamic result;
        if (profile.protocol == 'responses') {
          result = await network.post(uri, {
            'model': profile.model,
            'instructions': system,
            'input': user,
            'store': false,
            'text': {
              'format': {'type': 'json_object'},
            },
          }, token: key);
        } else {
          result = await network.post(uri, {
            'model': profile.model,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
            'response_format': {'type': 'json_object'},
          }, token: key);
        }
        final String text;
        if (profile.protocol == 'responses') {
          text = (result['output'] as List)
              .where((item) => item['type'] == 'message')
              .expand((item) => item['content'] as List)
              .where((item) => item['type'] == 'output_text')
              .map((item) => item['text'] as String)
              .join();
        } else {
          text = result['choices'][0]['message']['content'] as String;
        }
        return AiResult(Intent.parse(text), profile.name, attempts);
      } on ApiException catch (error) {
        attempts.add('${profile.name}: ${error.message}');
        if (settings.selectedProfile != 'auto' ||
            (!error.retryable && error.status != 401 && error.status != 403)) {
          rethrow;
        }
      } on PlatformException catch (error) {
        attempts.add('${profile.name}: ${error.message ?? error.code}');
        if (settings.selectedProfile != 'auto') rethrow;
      }
    }
    throw ApiException('Доступные профили не ответили. ${attempts.join('; ')}');
  }
}
