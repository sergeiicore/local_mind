import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/data/local_repository.dart';
import 'package:local_mind/domain/models.dart';

void main() {
  group('LocalRepository', () {
    late Directory directory;
    late LocalRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('local_mind_test_');
      repository = LocalRepository(directory);
      await repository.load();
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'keeps an imported thought only once when its file is unchanged',
      () async {
        final incoming = Directory('${directory.path}/incoming');
        await incoming.create();
        await File(
          '${incoming.path}/phone.md',
        ).writeAsString('Идея с телефона');

        expect(await repository.importFolder(incoming, 'obsidian'), 1);
        expect(await repository.importFolder(incoming, 'obsidian'), 0);
        expect(repository.entries, hasLength(1));
        expect(repository.entries.single.original, 'Идея с телефона');
      },
    );

    test('restores state after reload', () async {
      await repository.importText(
        identity: 'telegram:42:1',
        text: 'Напомнить про встречу',
        source: 'telegram',
      );
      final restored = LocalRepository(directory);
      await restored.load();

      expect(restored.entries.single.text, 'Напомнить про встречу');
      expect(restored.entries.single.source, 'telegram');
    });

    test('persists the active conversation and clears only chat', () async {
      await repository.addChatMessage(
        ChatMessage(
          id: 'message-1',
          role: ChatRole.user,
          text: 'Привет',
          createdAt: DateTime(2026, 9, 10),
        ),
      );
      await repository.importText(
        identity: 'note-1',
        text: 'Важная заметка',
        source: 'text',
      );

      final restored = LocalRepository(directory);
      await restored.load();
      expect(restored.chatMessages.single.text, 'Привет');

      await restored.clearChat();
      expect(restored.chatMessages, isEmpty);
      expect(restored.entries.single.text, 'Важная заметка');
    });
  });
}
