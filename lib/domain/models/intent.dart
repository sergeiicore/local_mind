import 'dart:convert';

class Intent {
  const Intent({
    required this.kind,
    required this.text,
    this.start,
    this.end,
    this.question,
  });

  final String kind;
  final String text;
  final DateTime? start;
  final DateTime? end;
  final String? question;

  factory Intent.parse(String response) {
    final json = jsonDecode(response) as Map<String, dynamic>;
    final kind = json['kind'];
    if (!['note', 'task', 'event', 'answer', 'clarification'].contains(kind)) {
      throw const FormatException('Неизвестное действие AI');
    }
    final text = json['text'];
    if (text is! String || text.trim().isEmpty || text.length > 20000) {
      throw const FormatException('AI вернул пустой или слишком большой текст');
    }
    final start = _parseDate(json['start']);
    final end = _parseDate(json['end']);
    if (kind == 'event' &&
        (start == null || end == null || !end.isAfter(start))) {
      throw const FormatException('У события нужны корректные начало и конец');
    }
    return Intent(
      kind: kind as String,
      text: text.trim(),
      start: start,
      end: end,
      question: json['question'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(raw)) {
      throw const FormatException('В дате отсутствует часовой пояс');
    }
    final date = DateTime.parse(raw).toLocal();
    if (date.year < 2020 || date.year > 2100) {
      throw const FormatException('Дата вне допустимого диапазона');
    }
    return date;
  }
}
