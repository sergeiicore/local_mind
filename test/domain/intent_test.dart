import 'package:flutter_test/flutter_test.dart';
import 'package:local_mind/domain/models.dart';

void main() {
  group('Intent.parse', () {
    test('accepts a fully specified event with timezone', () {
      final intent = Intent.parse('''
        {"kind":"event","text":"Созвон","start":"2026-09-10T15:00:00+03:00","end":"2026-09-10T16:00:00+03:00","question":null}
      ''');

      expect(intent.kind, 'event');
      expect(intent.text, 'Созвон');
      expect(intent.end, isNotNull);
      expect(intent.end!.isAfter(intent.start!), isTrue);
    });

    test('rejects an event without a complete time range', () {
      expect(
        () => Intent.parse(
          '{"kind":"event","text":"Созвон","start":null,"end":null}',
        ),
        throwsFormatException,
      );
    });

    test('rejects a date without an explicit timezone', () {
      expect(
        () => Intent.parse(
          '{"kind":"task","text":"Позвонить","start":"2026-09-10T15:00","end":null}',
        ),
        throwsFormatException,
      );
    });
  });
}
