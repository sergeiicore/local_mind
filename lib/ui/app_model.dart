import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/ai_service.dart';
import '../data/integrations.dart';
import '../data/local_repository.dart';
import '../data/native_service.dart';
import '../domain/models.dart';

class AppModel extends ChangeNotifier {
  AppModel({
    required this.repository,
    required this.native,
    required this.ai,
    required this.integrations,
  });
  final LocalRepository repository;
  final NativeService native;
  final AiService ai;
  final Integrations integrations;
  Settings get settings => repository.settings;
  List<Entry> get entries => repository.entries;
  List<ChatMessage> get chatMessages => repository.chatMessages;
  bool ready = false, busy = false, recording = false, syncing = false;
  int page = 0, captureRevision = 0;
  String? error, notice, syncError, aiProfile, attachmentName;
  String attachment = '', transcript = '';
  String _rules = '';
  Intent? intent;
  String intentOriginal = '';
  List<Map<String, dynamic>> calendars = [], events = [];
  bool calendarLoaded = false;
  Timer? _timer;
  VoidCallback? onCapture;
  ValueChanged<String>? onTranscript;

  Future<void> initialize({bool startTimer = true}) async {
    try {
      await repository.load();
      _rules = await rootBundle.loadString('assets/rules/assistant.md');
      final rulesFile = File('${repository.root.path}/Rules/assistant.md');
      await rulesFile.parent.create(recursive: true);
      if (!await rulesFile.exists()) await rulesFile.writeAsString(_rules);
      notice = repository.recoveryNotice;
      ready = true;
      if (startTimer) {
        await _connectCodexIfAvailable();
        NativeService.channel.setMethodCallHandler((call) async {
          switch (call.method) {
            case 'capture':
              page = 0;
              captureRevision++;
              notifyListeners();
              onCapture?.call();
              if (call.arguments == true && !recording) await toggleRecording();
            case 'transcript':
              transcript = call.arguments as String;
              onTranscript?.call(transcript);
            case 'speechEnded':
              recording = false;
              notifyListeners();
            case 'speechError':
              recording = false;
              error = call.arguments as String;
              notifyListeners();
            case 'wake':
              unawaited(sync());
            case 'navigate':
              page = call.arguments as int;
              notifyListeners();
          }
        });
        _timer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => unawaited(sync()),
        );
        unawaited(sync());
      }
    } catch (e) {
      error = 'Не удалось открыть Local Mind: $e';
    }
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !ready) return;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = friendlyError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String friendlyError(Object e) => e is PlatformException
      ? e.message ?? 'Ошибка macOS: ${e.code}'
      : e is FormatException
      ? e.message
      : e is FileSystemException
      ? 'Ошибка доступа к файлам: ${e.message}'
      : e.toString();

  Future<void> capture(String text, {String? source}) => run(() async {
    if (text.trim().isEmpty) {
      throw const FormatException('Сначала напишите или продиктуйте мысль');
    }
    if (text.length > 100000) {
      throw const FormatException('Запись должна быть короче 100 000 символов');
    }
    if (recording) await stopRecording();
    await repository.add(
      Entry(
        id: newId(),
        text: text.trim(),
        original: text,
        createdAt: DateTime.now(),
        source: source ?? (transcript.isEmpty ? 'text' : 'voice'),
      ),
    );
    transcript = '';
    notice = 'Сохранено на Mac';
    intent = null;
    unawaited(sync());
  });

  Future<void> _connectCodexIfAvailable() async {
    if (settings.profiles.isNotEmpty) return;
    try {
      final raw = await native.call<Map<dynamic, dynamic>>('codexStatus');
      if (raw?['installed'] != true) return;
      await repository.configure(
        (current) => current.copyWith(
          profiles: [
            AiProfile(
              id: newId(),
              name: 'Codex',
              endpoint: '',
              model: '',
              protocol: 'codex',
            ),
          ],
        ),
      );
    } catch (_) {
      // AI setup remains available in Settings when automatic discovery fails.
    }
  }

  Future<bool> sendMessage(String text) async {
    if (busy || !ready) return false;
    final input = text.trim();
    if (input.isEmpty) {
      error = 'Напишите или продиктуйте сообщение';
      notifyListeners();
      return false;
    }
    if (input.length > 20000) {
      error = 'Сообщение должно быть короче 20 000 символов';
      notifyListeners();
      return false;
    }

    busy = true;
    error = null;
    notice = null;
    intent = null;
    if (recording) await stopRecording();
    await repository.addChatMessage(
      ChatMessage(
        id: newId(),
        role: ChatRole.user,
        text: input,
        createdAt: DateTime.now(),
      ),
    );
    transcript = '';
    notifyListeners();
    unawaited(_resizeChat());

    try {
      final result = await _interpret(input);
      intentOriginal = input;
      aiProfile = result.profile;
      final action = result.intent;
      if (action.kind == 'answer' || action.kind == 'clarification') {
        intent = null;
      } else {
        intent = action;
      }
      await repository.addChatMessage(
        ChatMessage(
          id: newId(),
          role: ChatRole.assistant,
          text: switch (action.kind) {
            'answer' => action.text,
            'clarification' => action.question ?? action.text,
            'event' => 'Подготовил событие. Проверьте детали перед созданием.',
            'task' => 'Подготовил задачу. Проверьте срок и напоминание.',
            _ => 'Подготовил заметку. Проверьте текст перед сохранением.',
          },
          createdAt: DateTime.now(),
        ),
      );
      if (result.attempts.isNotEmpty) {
        notice = '${result.profile}: ${result.attempts.join('; ')}';
      }
    } catch (exception) {
      final message = friendlyError(exception);
      await repository.addChatMessage(
        ChatMessage(
          id: newId(),
          role: ChatRole.assistant,
          text: 'Не получилось ответить: $message',
          createdAt: DateTime.now(),
          isError: true,
        ),
      );
    } finally {
      busy = false;
      notifyListeners();
      unawaited(_resizeChat());
    }
    return true;
  }

  Future<AiResult> _interpret(String text, {bool includeToday = false}) async {
    final custom = File('${repository.root.path}/Rules/assistant.md');
    final rules = await custom.exists() ? await custom.readAsString() : _rules;
    final context = StringBuffer(attachment);
    final needsToday =
        includeToday ||
        RegExp(
          r'\b(сегодня|завтра|календар|расписан|план на день|что у меня|today|tomorrow|calendar|schedule)\b',
          caseSensitive: false,
        ).hasMatch(text);
    if (needsToday) {
      if (settings.calendarIdentifier.isNotEmpty) {
        events = await native.today();
        calendarLoaded = true;
      }
      context.write(
        '\nCalendar access loaded: $calendarLoaded.\n${jsonEncode(events)}',
      );
      context.write(
        '\nOpen local tasks: ${jsonEncode(entries.where((e) => e.kind == EntryKind.task && !e.done).take(100).map((e) => e.toJson()).toList())}',
      );
    }
    return ai.interpret(
      settings: settings,
      input: text,
      rules: rules,
      context: context.toString(),
      conversation: chatMessages
          .take(chatMessages.length - 1)
          .map(
            (message) => {'role': message.role.name, 'content': message.text},
          )
          .toList(),
    );
  }

  Future<void> interpret(String text, {bool includeToday = false}) async {
    await sendMessage(text);
  }

  Future<void> newChat() async {
    if (recording) await stopRecording();
    await repository.clearChat();
    intent = null;
    intentOriginal = '';
    transcript = '';
    attachment = '';
    attachmentName = null;
    error = null;
    notice = null;
    await _resizeChat(reset: true);
    notifyListeners();
  }

  /// The header action is contextual: outside the chat it returns to the
  /// current conversation; inside the chat it deliberately starts a new one.
  Future<void> openChatOrCreateNew() async {
    if (busy) return;
    if (page != 0) {
      await openPage(0);
      return;
    }
    await newChat();
  }

  Future<void> _resizeChat({bool reset = false}) async {
    try {
      await native.call<void>('resizeChat', {
        'messages': reset ? 0 : chatMessages.length,
        'hasAction': !reset && intent != null,
      });
    } catch (_) {
      // Resizing is visual polish and must never interrupt the conversation.
    }
  }

  void manualIntent(String text, String kind) {
    intentOriginal = text;
    intent = Intent(kind: kind, text: text);
    error = null;
    unawaited(_resizeChat());
    notifyListeners();
  }

  void dismissIntent() {
    intent = null;
    unawaited(_resizeChat());
    notifyListeners();
  }

  Future<void> confirm({
    required String text,
    required String kind,
    DateTime? start,
    DateTime? end,
    bool telegram = false,
    bool todoist = false,
    int reminderMinutes = 0,
  }) => run(() async {
    if (text.trim().isEmpty) throw const FormatException('Укажите текст');
    if (kind == 'event' &&
        (start == null || end == null || !end.isAfter(start))) {
      throw const FormatException('Укажите начало и конец события');
    }
    if (kind == 'event' && settings.calendarIdentifier.isEmpty) {
      throw const FormatException('Выберите календарь в настройках');
    }
    if (start != null && !start.isAfter(DateTime.now())) {
      throw const FormatException('Выберите время в будущем');
    }
    if (telegram &&
        (start == null ||
            !settings.telegramEnabled ||
            settings.telegramChat.isEmpty)) {
      throw const FormatException('Для Telegram нужны срок и подключённый бот');
    }
    if (reminderMinutes < 0 || reminderMinutes > 10080) {
      throw const FormatException('Напоминание: от 0 до 10080 минут');
    }
    final entry = Entry(
      id: newId(),
      text: text.trim(),
      original: intentOriginal,
      createdAt: DateTime.now(),
      kind: EntryKind.values.byName(kind),
      due: start,
      end: end,
      source: 'capture',
      calendarId: kind == 'event' ? 'pending' : null,
      todoistId: todoist && kind == 'task' ? 'pending' : null,
      telegramReminder: telegram,
      reminderMinutes: reminderMinutes,
    );
    await repository.add(entry);
    intent = null;
    await repository.addChatMessage(
      ChatMessage(
        id: newId(),
        role: ChatRole.assistant,
        text: 'Готово — запись сохранена.',
        createdAt: DateTime.now(),
      ),
    );
    await _resizeChat();
    await _deliver(entry);
    notice = 'Запись сохранена. Статус интеграций — во входящих.';
    unawaited(sync());
  });

  Future<void> _deliver(Entry entry) async {
    try {
      if (entry.calendarId == 'pending') {
        final id = await native.call<String>('createEvent', {
          'id': entry.id,
          'title': entry.text.split('\n').first,
          'notes': entry.text,
          'start': entry.due!.millisecondsSinceEpoch,
          'end': entry.end!.millisecondsSinceEpoch,
          'calendar': settings.calendarIdentifier,
          'reminderMinutes': entry.reminderMinutes,
        });
        if (id == null) {
          throw const FormatException(
            'Calendar не вернул идентификатор события',
          );
        }
        await repository.update(
          entry.id,
          (e) => e.copyWith(calendarId: id, clearError: true),
        );
      }
      if (entry.todoistId == 'pending') {
        final id = await integrations.createTodoist(entry);
        await repository.update(
          entry.id,
          (e) => e.copyWith(todoistId: id, clearError: true),
        );
      }
      if (entry.due != null && entry.kind != EntryKind.event) {
        await native.call<void>('notifyAt', {
          'id': entry.id,
          'title': 'Local Mind',
          'body': entry.text,
          'at': entry.notifyAt!.millisecondsSinceEpoch,
        });
      }
      await repository.update(entry.id, (e) => e.copyWith(clearError: true));
    } catch (e) {
      await repository.update(
        entry.id,
        (item) => item.copyWith(deliveryError: friendlyError(e)),
      );
    }
  }

  Future<void> retry(Entry entry) => run(() => _deliver(entry));

  Future<void> toggleDone(Entry entry) => run(() async {
    if (!entry.done &&
        entry.todoistId != null &&
        entry.todoistId != 'pending') {
      await integrations.closeTodoist(entry);
    }
    if (entry.done && entry.todoistId != null) {
      throw const FormatException(
        'Повторно открыть синхронизированную задачу можно в Todoist',
      );
    }
    await repository.update(entry.id, (e) => e.copyWith(done: !e.done));
    if (!entry.done) {
      await native.call<void>('cancelNotification', {'id': entry.id});
    }
  });

  Future<void> sync() async {
    if (!ready || syncing) return;
    syncing = true;
    final errors = <String>[];
    Future<void> step(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        errors.add('$name: ${friendlyError(e)}');
      }
    }

    await step('Локальные входящие', () async {
      await repository.importFolder(
        Directory('${repository.root.path}/Bridge/Incoming'),
        'agent',
      );
    });
    if (settings.vaultPath.isNotEmpty) {
      await step('Obsidian', () async {
        await repository.prepareVault(settings.vaultPath);
        await repository.importFolder(
          Directory('${settings.vaultPath}/Local Mind/Incoming'),
          'obsidian',
        );
        await repository.exportNotes();
      });
    }
    if (settings.telegramEnabled) {
      await step('Telegram', () async {
        await integrations.pollTelegram();
      });
      await step('Напоминания', _sendDueReminders);
    }
    syncError = errors.isEmpty ? null : errors.join('\n');
    syncing = false;
    notifyListeners();
  }

  Future<void> _sendDueReminders() async {
    final now = DateTime.now();
    for (final entry in entries.where(
      (e) =>
          e.telegramReminder &&
          !e.notified &&
          !e.done &&
          e.notifyAt != null &&
          !e.notifyAt!.isAfter(now),
    )) {
      if (entry.deliveryAttemptAt != null &&
          now.difference(entry.deliveryAttemptAt!) <
              const Duration(minutes: 5)) {
        continue;
      }
      await repository.update(
        entry.id,
        (e) => e.copyWith(deliveryAttemptAt: now),
      );
      try {
        await integrations.sendTelegram(
          'Напоминание · ${dayKey(entry.due!.toLocal())} ${clockLabel(entry.due!.toLocal())}\n\n${entry.text}\n\nLocal Mind · ${entry.id.substring(0, 6)}',
        );
        await repository.update(
          entry.id,
          (e) => e.copyWith(notified: true, clearError: true),
        );
      } catch (e) {
        await repository.update(
          entry.id,
          (item) =>
              item.copyWith(deliveryError: 'Telegram: ${friendlyError(e)}'),
        );
        rethrow;
      }
    }
  }

  Future<void> saveSettings(Settings Function(Settings) transform) =>
      run(() async {
        await repository.configure(transform);
        notice = 'Настройки сохранены';
      });

  Future<void> chooseVault() => run(() async {
    final path = await native.call<String>('chooseDirectory');
    if (path == null) return;
    await repository.prepareVault(path);
    await repository.configure((s) => s.copyWith(vaultPath: path));
    for (final e in entries) {
      await repository.update(e.id, (item) => item.copyWith(exported: false));
    }
    notice = 'Obsidian подключён: папка Local Mind';
    unawaited(sync());
  });

  Future<void> attachNote() => run(() async {
    final path = await native.call<String>('chooseMarkdown');
    if (path == null) return;
    final file = File(path);
    if (!path.toLowerCase().endsWith('.md') || await file.length() > 30000) {
      throw const FormatException('Выберите Markdown-файл до 30 КБ');
    }
    attachment = await file.readAsString();
    attachmentName = path.split('/').last;
  });
  void detachNote() {
    attachment = '';
    attachmentName = null;
    notifyListeners();
  }

  Future<void> loadCalendar() => run(() async {
    calendars = await native.calendars();
    events = await native.today();
    calendarLoaded = true;
  });

  Future<void> toggleRecording() async {
    if (recording) {
      await stopRecording();
      return;
    }
    error = null;
    transcript = '';
    try {
      await native.call<void>('startSpeech');
      recording = true;
    } catch (e) {
      error = friendlyError(e);
    }
    notifyListeners();
  }

  Future<void> stopRecording() async {
    await native.call<void>('stopSpeech');
    recording = false;
    notifyListeners();
  }

  Future<void> openPage(int index) async {
    page = index;
    try {
      if (index == 0) {
        await _resizeChat();
      } else {
        await native.call<void>('expandWindow', {'page': index});
      }
    } catch (exception) {
      // A window-resize failure must not take down navigation or the chat.
      error = friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
