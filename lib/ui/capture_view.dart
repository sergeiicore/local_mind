import 'package:flutter/material.dart' hide Intent;
import 'package:flutter/services.dart';

import '../domain/models.dart';
import 'app_model.dart';

class CaptureView extends StatefulWidget {
  const CaptureView({super.key, required this.model});
  final AppModel model;
  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> {
  final text = TextEditingController();
  final focus = FocusNode();
  String voiceBase = '';
  @override
  void initState() {
    super.initState();
    widget.model.onCapture = () {
      voiceBase = text.text;
      focus.requestFocus();
    };
    widget.model.onTranscript = (value) {
      text.text = '${voiceBase.isEmpty ? '' : '$voiceBase\n'}$value';
      text.selection = TextSelection.collapsed(offset: text.text.length);
    };
  }

  @override
  void dispose() {
    widget.model.onCapture = null;
    widget.model.onTranscript = null;
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    await widget.model.capture(text.text);
    if (widget.model.error == null && mounted) text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (!model.busy) save();
        },
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  key: const Key('capture-input'),
                  controller: text,
                  focusNode: focus,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 100000,
                  style: const TextStyle(fontSize: 16, height: 1.45),
                  decoration: InputDecoration(
                    hintText: model.recording
                        ? 'Слушаю…'
                        : 'Напишите мысль или задайте вопрос…',
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (model.intent != null) model.dismissIntent();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 0, 7, 7),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: model.recording
                            ? 'Остановить диктовку'
                            : 'Продиктовать',
                        onPressed: model.busy
                            ? null
                            : () {
                                if (!model.recording) voiceBase = text.text;
                                model.toggleRecording();
                              },
                        icon: Icon(
                          model.recording
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none_rounded,
                          size: 19,
                        ),
                        color: model.recording
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      IconButton(
                        tooltip:
                            model.attachmentName ?? 'Приложить одну заметку',
                        onPressed: model.busy ? null : model.attachNote,
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Создать без AI',
                        onSelected: (kind) =>
                            model.manualIntent(text.text, kind),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'event',
                            child: Text('Событие в календаре'),
                          ),
                          PopupMenuItem(
                            value: 'task',
                            child: Text('Задача / напоминание'),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz_rounded, size: 19),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Разобрать или спросить AI',
                        onPressed: model.busy
                            ? null
                            : () => model.interpret(text.text),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                      ),
                      const SizedBox(width: 5),
                      IconButton.filled(
                        key: const Key('save-note'),
                        tooltip: 'Сохранить дословно · ⌘ Enter',
                        onPressed: model.busy ? null : save,
                        icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (model.recording)
            Padding(
              padding: const EdgeInsets.only(top: 9, left: 5),
              child: Text(
                '● Слушаю на Mac',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (model.attachmentName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InputChip(
                avatar: const Icon(Icons.description_outlined, size: 15),
                label: Text(model.attachmentName!),
                onDeleted: model.detachNote,
              ),
            ),
          if (model.intent != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IntentCard(
                key: ObjectKey(model.intent),
                model: model,
                intent: model.intent!,
              ),
            ),
        ],
      ),
    );
  }
}

class IntentCard extends StatefulWidget {
  const IntentCard({super.key, required this.model, required this.intent});
  final AppModel model;
  final Intent intent;
  @override
  State<IntentCard> createState() => _IntentCardState();
}

class _IntentCardState extends State<IntentCard> {
  late final title = TextEditingController(text: widget.intent.text);
  late final start = TextEditingController(text: _format(widget.intent.start));
  late final end = TextEditingController(text: _format(widget.intent.end));
  final minutes = TextEditingController(text: '0');
  bool telegram = false, todoist = false;
  String? validation;
  String _format(DateTime? date) =>
      date == null ? '' : '${dayKey(date)} ${clockLabel(date)}';
  DateTime? _parse(String value) {
    if (value.trim().isEmpty) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
    ).firstMatch(value.trim());
    if (match == null) {
      throw const FormatException('Формат даты: 2026-09-10 15:00');
    }
    final values = List.generate(5, (i) => int.parse(match.group(i + 1)!));
    final date = DateTime(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
    );
    if (_format(date) != value.trim()) {
      throw const FormatException('Такой даты или времени не существует');
    }
    return date;
  }

  @override
  void dispose() {
    title.dispose();
    start.dispose();
    end.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final model = widget.model;
    if (intent.kind == 'answer' || intent.kind == 'clarification') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                intent.kind == 'answer'
                    ? 'Ответ · ${model.aiProfile ?? 'AI'}'
                    : 'Нужно уточнение',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SelectableText(intent.question ?? intent.text),
              const SizedBox(height: 12),
              TextButton(
                onPressed: model.dismissIntent,
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (intent.kind) {
                      'event' => 'Событие в календаре',
                      'task' => 'Задача / напоминание',
                      _ => 'Заметка',
                    },
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: model.dismissIntent,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              minLines: 1,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Текст'),
            ),
            if (intent.kind != 'note') ...[
              const SizedBox(height: 14),
              TextField(
                controller: start,
                decoration: InputDecoration(
                  labelText: intent.kind == 'event'
                      ? 'Начало · местное время'
                      : 'Срок · необязательно',
                  hintText: '2026-09-10 15:00',
                ),
              ),
              if (intent.kind == 'event') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(
                    labelText: 'Конец · местное время',
                    hintText: '2026-09-10 16:00',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText:
                      'Напомнить за столько минут (0 — в момент события)',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Напоминание в Telegram'),
                subtitle: const Text(
                  'Mac должен быть включён и подключён к сети',
                ),
                value: telegram,
                onChanged: model.settings.telegramEnabled
                    ? (v) => setState(() => telegram = v!)
                    : null,
              ),
              if (intent.kind == 'task')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Также создать в Todoist'),
                  value: todoist,
                  onChanged: model.settings.todoistEnabled
                      ? (v) => setState(() => todoist = v!)
                      : null,
                ),
            ],
            if (validation != null)
              Text(
                validation!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: model.busy
                  ? null
                  : () {
                      try {
                        final date = _parse(start.text),
                            finish = _parse(end.text);
                        final lead = int.tryParse(minutes.text);
                        if (lead == null) {
                          throw const FormatException(
                            'Укажите целое число минут',
                          );
                        }
                        setState(() => validation = null);
                        model.confirm(
                          text: title.text,
                          kind: intent.kind,
                          start: date,
                          end: finish,
                          telegram: telegram,
                          todoist: todoist,
                          reminderMinutes: lead,
                        );
                      } on FormatException catch (e) {
                        setState(() => validation = e.message);
                      }
                    },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}
