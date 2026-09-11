import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/domain/models.dart';

void main() {
  test('Codex profile preserves its model and reasoning selection', () {
    const profile = AiProfile(
      id: 'codex',
      name: 'Codex',
      endpoint: '',
      model: 'gpt-5.3-codex',
      protocol: 'codex',
      reasoningEffort: 'high',
    );

    final restored = AiProfile.fromJson(profile.toJson());

    expect(restored.model, 'gpt-5.3-codex');
    expect(restored.reasoningEffort, 'high');
    expect(restored.isCodex, isTrue);
  });
}
