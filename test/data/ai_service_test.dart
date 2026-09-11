import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/data/ai_service.dart';
import 'package:local_mind/domain/models.dart';

void main() {
  group('AiService.candidates', () {
    test('keeps Codex available when only local profiles are allowed', () {
      const codex = AiProfile(
        id: 'codex',
        name: 'Codex',
        endpoint: '',
        model: '',
        protocol: 'codex',
      );
      const cloud = AiProfile(
        id: 'cloud',
        name: 'Cloud',
        endpoint: 'https://example.com/v1',
        model: 'model',
      );

      final candidates = AiService.candidates(
        const Settings(profiles: [codex, cloud]),
      );

      expect(candidates, [codex]);
      expect(codex.isCodex, isTrue);
      expect(codex.providerLabel, 'Текущий вход Codex');
    });

    test('respects a specifically selected profile', () {
      const first = AiProfile(
        id: 'first',
        name: 'First',
        endpoint: 'http://localhost:11434/v1',
        model: 'one',
      );
      const second = AiProfile(
        id: 'second',
        name: 'Second',
        endpoint: 'http://localhost:11434/v1',
        model: 'two',
      );

      final candidates = AiService.candidates(
        const Settings(profiles: [first, second], selectedProfile: 'second'),
      );

      expect(candidates, [second]);
    });
  });

  group('AiService conversation context', () {
    test('keeps recent role-tagged messages within the context limit', () {
      final history = AiService.conversationForRequest([
        {'role': 'system', 'content': 'ignore'},
        {'role': 'user', 'content': 'Мой любимый цвет — зелёный.'},
        {'role': 'assistant', 'content': 'Запомнил: зелёный.'},
      ]);

      expect(history, [
        {'role': 'user', 'content': 'Мой любимый цвет — зелёный.'},
        {'role': 'assistant', 'content': 'Запомнил: зелёный.'},
      ]);
    });

    test('Codex prompt places history before the current request', () {
      final prompt = AiService.codexPrompt(
        instructions: 'Follow the JSON contract.',
        conversation: [
          {'role': 'user', 'content': 'Меня зовут Сергей.'},
          {'role': 'assistant', 'content': 'Приятно познакомиться, Сергей.'},
        ],
        input: 'Как меня зовут?',
      );

      expect(prompt, contains('user: Меня зовут Сергей.'));
      expect(prompt, contains('assistant: Приятно познакомиться, Сергей.'));
      expect(prompt, endsWith('user: Как меня зовут?'));
    });
  });
}
