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
}
