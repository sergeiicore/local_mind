import 'dart:async';

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
  final composer = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  String voiceBase = '';
  String voiceTranscript = '';
  int previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    previousMessageCount = widget.model.chatMessages.length;
    focus.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.enter) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        _insertLineBreak();
        return KeyEventResult.handled;
      }
      if (!widget.model.busy) unawaited(send());
      return KeyEventResult.handled;
    };
    widget.model.addListener(_modelChanged);
    widget.model.onCapture = () {
      voiceBase = composer.text;
      voiceTranscript = '';
      focus.requestFocus();
    };
    widget.model.onTranscript = (value) {
      // Speech recognition sends partial results. An empty intermediate result
      // must not erase the text that the user has already dictated.
      if (value.trim().isEmpty) return;
      voiceTranscript = value;
      composer.text =
          '${voiceBase.isEmpty ? '' : '$voiceBase\n'}$voiceTranscript';
      composer.selection = TextSelection.collapsed(
        offset: composer.text.length,
      );
    };
  }

  void _modelChanged() {
    final count = widget.model.chatMessages.length;
    if (count == previousMessageCount) return;
    previousMessageCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    widget.model.onCapture = null;
    widget.model.onTranscript = null;
    widget.model.removeListener(_modelChanged);
    composer.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final draft = composer.text;
    if (draft.trim().isEmpty || widget.model.busy) {
      focus.requestFocus();
      return;
    }
    final accepted = await widget.model.sendMessage(draft);
    if (accepted && mounted && composer.text == draft) {
      composer.clear();
      voiceBase = '';
      voiceTranscript = '';
    }
    if (mounted) focus.requestFocus();
  }

  void _insertLineBreak() {
    final selection = composer.selection;
    final start = selection.isValid ? selection.start : composer.text.length;
    final end = selection.isValid ? selection.end : composer.text.length;
    if (composer.text.length - (end - start) >= 20000) return;
    final text = composer.text.replaceRange(start, end, '\n');
    composer.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final messages = model.chatMessages;
    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: messages.isEmpty && model.intent == null
                ? const EmptyConversation(key: ValueKey('empty'))
                : ListView.builder(
                    key: const ValueKey('conversation'),
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    itemCount:
                        messages.length +
                        (model.busy ? 1 : 0) +
                        (model.intent == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index < messages.length) {
                        return ChatBubble(
                          key: ValueKey(messages[index].id),
                          message: messages[index],
                        );
                      }
                      if (model.busy && index == messages.length) {
                        return const _ThinkingBubble();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IntentCard(
                          key: ObjectKey(model.intent),
                          model: model,
                          intent: model.intent!,
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (model.attachmentName != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InputChip(
                avatar: const Icon(Icons.description_outlined, size: 14),
                label: Text(model.attachmentName!),
                onDeleted: model.detachNote,
              ),
            ),
          ),
        _Composer(
          controller: composer,
          focusNode: focus,
          model: model,
          onSend: send,
          onVoice: () {
            if (!model.recording) voiceBase = composer.text;
            model.toggleRecording();
          },
        ),
      ],
    );
  }
}

class EmptyConversation extends StatelessWidget {
  const EmptyConversation({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 150;
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: compact ? 6 : 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.blur_on_rounded,
                    size: 19,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 11),
              ],
              Text(
                'О чём думаете?',
                style: TextStyle(
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                compact
                    ? 'Напишите или продиктуйте сообщение'
                    : 'Напишите сообщение или продиктуйте его —\nответ останется в этом диалоге.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - value)),
          child: child,
        ),
      ),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: user
                ? scheme.primary.withValues(alpha: .11)
                : message.isError
                ? scheme.errorContainer.withValues(alpha: .55)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(user ? 14 : 4),
              bottomRight: Radius.circular(user ? 4 : 14),
            ),
          ),
          child: SelectableText(
            message.text,
            style: const TextStyle(fontSize: 14, height: 1.42),
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 1.6),
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.model,
    required this.onSend,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AppModel model;
  final VoidCallback onSend;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: model.recording
                ? scheme.error.withValues(alpha: .55)
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('chat-input'),
              controller: controller,
              focusNode: focusNode,
              readOnly: model.busy,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              maxLength: 20000,
              style: const TextStyle(fontSize: 14.5, height: 1.4),
              decoration: InputDecoration(
                hintText: model.recording
                    ? 'Слушаю…'
                    : 'Сообщение для Local Mind',
                counterText: '',
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 6, 5),
              child: Row(
                children: [
                  IconButton(
                    tooltip: model.recording
                        ? 'Остановить диктовку'
                        : 'Продиктовать',
                    onPressed: model.busy ? null : onVoice,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        model.recording
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        key: ValueKey(model.recording),
                        size: 18,
                      ),
                    ),
                    color: model.recording ? scheme.error : null,
                  ),
                  IconButton(
                    tooltip: model.attachmentName ?? 'Приложить заметку',
                    onPressed: model.busy ? null : model.attachNote,
                    icon: const Icon(Icons.attach_file_rounded, size: 17),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Создать без AI',
                    onSelected: (kind) =>
                        model.manualIntent(controller.text, kind),
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
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final canSend =
                          !model.busy && value.text.trim().isNotEmpty;
                      return Semantics(
                        button: true,
                        enabled: canSend,
                        child: ExcludeSemantics(
                          child: IconButton.filled(
                            key: const Key('chat-send-button'),
                            tooltip: 'Отправить',
                            // Keep the arrow visible for an empty draft. The
                            // no-op still prevents an empty request; a normal
                            // disabled IconButton fades it out on macOS.
                            onPressed: () {
                              if (canSend) onSend();
                            },
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: canSend
                                  ? scheme.primary
                                  : scheme.surfaceContainerHigh,
                              foregroundColor: canSend
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                              minimumSize: const Size(34, 34),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
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
