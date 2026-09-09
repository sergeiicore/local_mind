import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import 'app_model.dart';
import 'capture_view.dart';
import 'settings_view.dart';

class LocalMindApp extends StatelessWidget {
  const LocalMindApp({super.key, required this.model});
  final AppModel model;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff546b64),
      brightness: brightness,
      surface: dark ? const Color(0xff202224) : const Color(0xfffafaf9),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: '.AppleSystemUIFont',
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.compact,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff292c2d) : const Color(0xfff0f1ef),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xff292c2d) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Local Mind',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: AppView(model: model),
  );
}

class AppView extends StatelessWidget {
  const AppView({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          model.native.call<void>('hideWindow');
        },
      },
      child: Scaffold(
        body: Column(
          children: [
            _PanelHeader(model: model),
            const Divider(height: 1),
            Expanded(
              child: !model.ready
                  ? Center(
                      child: model.error == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: SelectableText(model.error!),
                            ),
                    )
                  : IndexedStack(
                      index: model.page,
                      children: [
                        CaptureView(model: model),
                        InboxView(model: model),
                        SettingsView(model: model),
                      ],
                    ),
            ),
            if (model.busy) const LinearProgressIndicator(minHeight: 2),
            if (model.ready &&
                (model.error != null ||
                    model.notice != null ||
                    model.syncError != null))
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      model.error != null || model.syncError != null
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.error ?? model.notice ?? model.syncError!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.blur_on, size: 17),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Local Mind',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          _destination(0, Icons.add_rounded, 'Новая мысль'),
          _destination(1, Icons.history_rounded, 'История'),
          _destination(2, Icons.tune_rounded, 'Настройки'),
          IconButton(
            tooltip: 'Закрыть · Esc',
            onPressed: () => model.native.call<void>('hideWindow'),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    ),
  );

  Widget _destination(int page, IconData icon, String tooltip) => IconButton(
    tooltip: tooltip,
    isSelected: model.page == page,
    onPressed: () => model.openPage(page),
    icon: Icon(icon, size: 18),
    selectedIcon: Icon(icon, size: 18),
    style: IconButton.styleFrom(
      backgroundColor: model.page == page
          ? const Color(0xff6d8f84).withValues(alpha: .18)
          : Colors.transparent,
    ),
  );
}

class InboxView extends StatefulWidget {
  const InboxView({super.key, required this.model});
  final AppModel model;
  @override
  State<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<InboxView> {
  String query = '';
  bool tasksOnly = false;
  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final entries = model.entries
        .where(
          (e) =>
              (!tasksOnly || e.kind == EntryKind.task) &&
              '${e.text} ${e.original}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Входящие',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Синхронизировать',
                onPressed: model.syncing ? null : model.sync,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${model.entries.length} записей · хранятся на этом Mac',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Поиск по вашим записям',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          FilterChip(
            label: const Text('Только задачи'),
            selected: tasksOnly,
            onSelected: (v) => setState(() => tasksOnly = v),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Здесь появятся ваши мысли',
                    subtitle:
                        'Запишите первую мысль или подключите\nObsidian и Telegram в настройках.',
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) =>
                        EntryCard(entry: entries[i], model: model),
                  ),
          ),
        ],
      ),
    );
  }
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry, required this.model});
  final Entry entry;
  final AppModel model;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.kind == EntryKind.task)
                SizedBox(
                  width: 30,
                  height: 26,
                  child: Checkbox(
                    value: entry.done,
                    onChanged: model.busy
                        ? null
                        : (_) => model.toggleDone(entry),
                  ),
                ),
              Expanded(
                child: SelectableText(
                  entry.text,
                  style: TextStyle(
                    height: 1.5,
                    decoration: entry.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Действия с записью',
                onSelected: (value) {
                  if (value == 'copy') {
                    Clipboard.setData(ClipboardData(text: entry.text));
                  }
                  if (value == 'original') {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Исходная запись'),
                        content: SizedBox(
                          width: 500,
                          child: SingleChildScrollView(
                            child: SelectableText(entry.original),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Закрыть'),
                          ),
                        ],
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Скопировать'),
                  ),
                  const PopupMenuItem(
                    value: 'original',
                    child: Text('Исходная запись'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                '${dayKey(entry.createdAt.toLocal())} · ${clockLabel(entry.createdAt.toLocal())}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(entry.source, style: Theme.of(context).textTheme.labelSmall),
              if (entry.due != null)
                Text(
                  '◷ ${dayKey(entry.due!.toLocal())} ${clockLabel(entry.due!.toLocal())}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (entry.calendarId != null)
                Text(
                  entry.calendarId == 'pending'
                      ? 'Calendar · ожидает'
                      : 'Calendar ✓',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (entry.todoistId != null)
                Text(
                  entry.todoistId == 'pending'
                      ? 'Todoist · ожидает'
                      : 'Todoist ✓',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (entry.telegramReminder)
                Text(
                  entry.notified
                      ? 'Telegram · отправлено'
                      : 'Telegram · запланировано',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          if (entry.deliveryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.deliveryError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: model.busy ? null : () => model.retry(entry),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}
