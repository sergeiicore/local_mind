import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/data/local_repository.dart';

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
  });
}
