import 'dart:io';

import 'package:flutter/material.dart' hide Intent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/data/ai_service.dart';
import 'package:local_mind/data/integrations.dart';
import 'package:local_mind/data/local_repository.dart';
import 'package:local_mind/data/native_service.dart';
import 'package:local_mind/data/network_service.dart';
import 'package:local_mind/domain/models.dart';
import 'package:local_mind/ui/app_model.dart';
import 'package:local_mind/ui/capture_view.dart';

class _Native extends NativeService {
  @override
  Future<T?> call<T>(String method, [Map<String, dynamic>? args]) async => null;
}

class _Ai extends AiService {
  _Ai(super.network, super.native);

  List<Map<String, String>>? receivedConversation;

  @override
  Future<AiResult> interpret({
    required Settings settings,
    required String input,
    required String rules,
    String context = '',
    List<Map<String, String>> conversation = const [],
  }) async {
    receivedConversation = conversation;
    return const AiResult(
      Intent(kind: 'answer', text: 'Привет! Чем помочь?'),
      'Test AI',
      [],
    );
  }
}

class _ComposerModel extends AppModel {
  _ComposerModel({
    required super.repository,
    required super.native,
    required super.ai,
    required super.integrations,
  });

  String? sentText;

  @override
  Future<bool> sendMessage(String text) {
    sentText = text;
    return Future.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sending keeps both sides of the conversation', () async {
    final directory = await Directory.systemTemp.createTemp('local_mind_chat_');
    addTearDown(() => directory.delete(recursive: true));
    final native = _Native();
    final network = NetworkService();
    final repository = LocalRepository(directory);
    final model = AppModel(
      repository: repository,
      native: native,
      ai: _Ai(network, native),
      integrations: Integrations(network, native, repository),
    );
    await model.initialize(startTimer: false);

    expect(await model.sendMessage('Привет'), isTrue);
    expect(model.chatMessages.map((message) => message.text), [
      'Привет',
      'Привет! Чем помочь?',
    ]);

    final restored = LocalRepository(directory);
    await restored.load();
    expect(restored.chatMessages, hasLength(2));
  });

  test(
    'header plus returns to the current chat before starting a new one',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'local_mind_plus_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final native = _Native();
      final network = NetworkService();
      final model = AppModel(
        repository: LocalRepository(directory),
        native: native,
        ai: _Ai(network, native),
        integrations: Integrations(network, native, LocalRepository(directory)),
      );
      await model.initialize(startTimer: false);
      await model.sendMessage('Сохрани этот диалог');

      await model.openPage(2);
      await model.openChatOrCreateNew();
      expect(model.page, 0);
      expect(model.chatMessages, hasLength(2));

      await model.openChatOrCreateNew();
      expect(model.page, 0);
      expect(model.chatMessages, isEmpty);
    },
  );

  test('the next request receives the previous complete chat turn', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local_mind_context_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final native = _Native();
    final network = NetworkService();
    final ai = _Ai(network, native);
    final repository = LocalRepository(directory);
    final model = AppModel(
      repository: repository,
      native: native,
      ai: ai,
      integrations: Integrations(network, native, repository),
    );
    await model.initialize(startTimer: false);

    await model.sendMessage('Запомни: я работаю из дома.');
    await model.sendMessage('Откуда я работаю?');

    expect(ai.receivedConversation, [
      {'role': 'user', 'content': 'Запомни: я работаю из дома.'},
      {'role': 'assistant', 'content': 'Привет! Чем помочь?'},
    ]);
  });

  testWidgets('chat bubble renders selectable message text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: ChatMessage(
              id: 'assistant-1',
              role: ChatRole.assistant,
              text: 'Ответ остаётся в чате',
              createdAt: DateTime(2026, 9, 10),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ответ остаётся в чате'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('empty chat fits the compact macOS window', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 430, height: 90, child: EmptyConversation()),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('О чём думаете?'), findsOneWidget);
  });

  testWidgets('Enter sends and Shift+Enter keeps a multiline draft', (
    tester,
  ) async {
    final native = _Native();
    final network = NetworkService();
    final model = _ComposerModel(
      repository: LocalRepository(Directory.current),
      native: native,
      ai: _Ai(network, native),
      integrations: Integrations(
        network,
        native,
        LocalRepository(Directory.current),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CaptureView(model: model)),
      ),
    );

    final input = find.byKey(const Key('chat-input'));
    await tester.enterText(input, 'Первая строка');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(tester.widget<TextField>(input).controller!.text, 'Первая строка\n');
    expect(model.sentText, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(model.sentText, 'Первая строка\n');
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
  });

  testWidgets('send button submits a non-empty draft', (tester) async {
    final native = _Native();
    final network = NetworkService();
    final model = _ComposerModel(
      repository: LocalRepository(Directory.current),
      native: native,
      ai: _Ai(network, native),
      integrations: Integrations(
        network,
        native,
        LocalRepository(Directory.current),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CaptureView(model: model)),
      ),
    );

    final button = find.byKey(const Key('chat-send-button'));
    await tester.tap(button);
    expect(model.sentText, isNull);
    await tester.enterText(find.byKey(const Key('chat-input')), 'Отправь это');
    await tester.pump();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pump();
    expect(model.sentText, 'Отправь это');
  });

  testWidgets('empty speech updates do not erase an existing dictation', (
    tester,
  ) async {
    final native = _Native();
    final network = NetworkService();
    final model = _ComposerModel(
      repository: LocalRepository(Directory.current),
      native: native,
      ai: _Ai(network, native),
      integrations: Integrations(
        network,
        native,
        LocalRepository(Directory.current),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CaptureView(model: model)),
      ),
    );

    model.onCapture!.call();
    model.onTranscript!.call('Записанный голосом текст');
    model.onTranscript!.call('');
    await tester.pump();

    final input = find.byKey(const Key('chat-input'));
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Записанный голосом текст',
    );
  });
}
