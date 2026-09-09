enum EntryKind { note, task, event }

class Entry {
  const Entry({
    required this.id,
    required this.text,
    required this.original,
    required this.createdAt,
    this.kind = EntryKind.note,
    this.source = 'text',
    this.due,
    this.end,
    this.done = false,
    this.calendarId,
    this.todoistId,
    this.telegramReminder = false,
    this.reminderMinutes = 0,
    this.notified = false,
    this.exported = false,
    this.deliveryError,
    this.deliveryAttemptAt,
  });

  final String id;
  final String text;
  final String original;
  final String source;
  final DateTime createdAt;
  final EntryKind kind;
  final DateTime? due;
  final DateTime? end;
  final DateTime? deliveryAttemptAt;
  final bool done;
  final bool telegramReminder;
  final bool notified;
  final bool exported;
  final String? calendarId;
  final String? todoistId;
  final String? deliveryError;
  final int reminderMinutes;

  DateTime? get notifyAt => due?.subtract(Duration(minutes: reminderMinutes));

  Entry copyWith({
    bool? done,
    String? calendarId,
    String? todoistId,
    bool? notified,
    bool? exported,
    String? deliveryError,
    bool clearError = false,
    DateTime? deliveryAttemptAt,
  }) => Entry(
    id: id,
    text: text,
    original: original,
    createdAt: createdAt,
    kind: kind,
    source: source,
    due: due,
    end: end,
    done: done ?? this.done,
    calendarId: calendarId ?? this.calendarId,
    todoistId: todoistId ?? this.todoistId,
    telegramReminder: telegramReminder,
    reminderMinutes: reminderMinutes,
    notified: notified ?? this.notified,
    exported: exported ?? this.exported,
    deliveryError: clearError ? null : deliveryError ?? this.deliveryError,
    deliveryAttemptAt: deliveryAttemptAt ?? this.deliveryAttemptAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'original': original,
    'createdAt': createdAt.toIso8601String(),
    'kind': kind.name,
    'source': source,
    'due': due?.toIso8601String(),
    'end': end?.toIso8601String(),
    'done': done,
    'calendarId': calendarId,
    'todoistId': todoistId,
    'telegramReminder': telegramReminder,
    'reminderMinutes': reminderMinutes,
    'notified': notified,
    'exported': exported,
    'deliveryError': deliveryError,
    'deliveryAttemptAt': deliveryAttemptAt?.toIso8601String(),
  };

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    id: json['id'] as String,
    text: json['text'] as String,
    original: json['original'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    kind: EntryKind.values.byName(json['kind'] as String),
    source: json['source'] as String? ?? 'text',
    due: DateTime.tryParse(json['due'] as String? ?? ''),
    end: DateTime.tryParse(json['end'] as String? ?? ''),
    done: json['done'] == true,
    calendarId: json['calendarId'] as String?,
    todoistId: json['todoistId'] as String?,
    telegramReminder: json['telegramReminder'] == true,
    reminderMinutes: json['reminderMinutes'] as int? ?? 0,
    notified: json['notified'] == true,
    exported: json['exported'] == true,
    deliveryError: json['deliveryError'] as String?,
    deliveryAttemptAt: DateTime.tryParse(
      json['deliveryAttemptAt'] as String? ?? '',
    ),
  );
}
