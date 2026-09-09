import '../domain/models.dart';
import 'local_repository.dart';
import 'native_service.dart';
import 'network_service.dart';

class Integrations {
  Integrations(this.network, this.native, this.repository);
  final NetworkService network;
  final NativeService native;
  final LocalRepository repository;

  Future<dynamic> telegram(String method, Map<String, dynamic> args) async {
    final token = await native.secret('telegram');
    if (token == null || token.isEmpty) {
      throw const FormatException('Укажите токен Telegram-бота');
    }
    if (!RegExp(r'^\d+:[A-Za-z0-9_-]+$').hasMatch(token)) {
      throw const FormatException('Некорректный токен Telegram-бота');
    }
    final dynamic result = await network.post(
      Uri.parse('https://api.telegram.org/bot$token/$method'),
      args,
    );
    if (result['ok'] != true) {
      throw const ApiException('Telegram отклонил запрос');
    }
    return result['result'];
  }

  Future<void> sendTelegram(String text) async {
    final chat = repository.settings.telegramChat;
    if (!RegExp(r'^\d+$').hasMatch(chat)) {
      throw const FormatException('Укажите ID вашего личного чата с ботом');
    }
    await telegram('sendMessage', {
      'chat_id': chat,
      'text': text.length > 4000 ? '${text.substring(0, 3990)}…' : text,
    });
  }

  Future<int> pollTelegram() async {
    final settings = repository.settings;
    if (!settings.telegramEnabled || settings.telegramChat.isEmpty) return 0;
    final updates =
        await telegram('getUpdates', {
              'offset': settings.telegramOffset,
              'timeout': 0,
              'limit': 100,
              'allowed_updates': ['message'],
            })
            as List;
    var count = 0;
    for (final dynamic update in updates) {
      final id = update['update_id'] as int;
      final dynamic message = update['message'];
      if (message != null &&
          message['chat']['id'].toString() == settings.telegramChat &&
          message['chat']['type'] == 'private') {
        final text =
            message['text'] as String? ?? message['caption'] as String?;
        if (text != null && !text.startsWith('/')) {
          if (await repository.importText(
            identity:
                'telegram:${settings.telegramChat}:${message['message_id']}',
            text: text,
            source: 'telegram',
          )) {
            count++;
          }
        }
      }
      // Offset only advances after the message is safely persisted.
      await repository.configure((s) => s.copyWith(telegramOffset: id + 1));
    }
    return count;
  }

  Future<String> createTodoist(Entry entry) async {
    final token = await native.secret('todoist');
    if (token == null || token.isEmpty) {
      throw const FormatException('Укажите API-токен Todoist');
    }
    final dynamic result = await network.post(
      Uri.parse('https://api.todoist.com/api/v1/tasks'),
      {
        'content': entry.text.split('\n').first,
        'description': entry.text,
        if (entry.due != null)
          'due_datetime': entry.due!.toUtc().toIso8601String(),
      },
      token: token,
      headers: {'X-Request-Id': entry.id},
    );
    return result['id'].toString();
  }

  Future<void> closeTodoist(Entry entry) async {
    final token = await native.secret('todoist');
    if (token == null || token.isEmpty) {
      throw const FormatException('Укажите API-токен Todoist');
    }
    // Todoist close returns HTTP 204; use the dedicated native-free network path.
    await network.post(
      Uri.parse(
        'https://api.todoist.com/api/v1/tasks/${entry.todoistId}/close',
      ),
      {},
      token: token,
    );
  }
}
