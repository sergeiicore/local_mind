import 'package:flutter/material.dart';

import 'app_model.dart';
import 'settings/ai_profiles_dialog.dart';
import 'settings/credentials_dialog.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    children: [
      const Text(
        'Подключения',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(
        'Настройте один раз — дальше всё работает из панели.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _row(
              icon: Icons.folder_outlined,
              title: 'Obsidian',
              subtitle: model.settings.vaultPath.isEmpty
                  ? 'Не подключён'
                  : 'Local Mind в вашем vault',
              connected: model.settings.vaultPath.isNotEmpty,
              onTap: model.chooseVault,
            ),
            _divider,
            _row(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar',
              subtitle: model.settings.calendarIdentifier.isEmpty
                  ? 'Не выбран'
                  : _calendarName,
              connected: model.settings.calendarIdentifier.isNotEmpty,
              onTap: () => _calendar(context),
            ),
            _divider,
            _row(
              icon: Icons.send_outlined,
              title: 'Telegram',
              subtitle: model.settings.telegramEnabled
                  ? 'Бот и напоминания включены'
                  : 'Не подключён',
              connected: model.settings.telegramEnabled,
              onTap: () => _telegram(context),
            ),
            _divider,
            _row(
              icon: Icons.check_circle_outline,
              title: 'Todoist',
              subtitle: model.settings.todoistEnabled
                  ? 'Создание задач включено'
                  : 'Не подключён',
              connected: model.settings.todoistEnabled,
              onTap: () => _todoist(context),
            ),
            _divider,
            _row(
              icon: Icons.auto_awesome_outlined,
              title: 'AI',
              subtitle: _aiLabel,
              connected: model.settings.profiles.isNotEmpty,
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AiProfilesDialog(model: model),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _utilityRow(
              context,
              icon: Icons.folder_copy_outlined,
              title: 'Локальные данные',
              onTap: () => model.native.call<void>('openPath', {
                'path': model.repository.root.path,
              }),
            ),
            _divider,
            _utilityRow(
              context,
              icon: Icons.tune_outlined,
              title: 'Правила AI · Markdown',
              onTap: () => model.native.call<void>('openPath', {
                'path': '${model.repository.root.path}/Rules/assistant.md',
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: Text(
          '⌃⌥Space · текст   ⌃⌥⇧Space · голос',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ],
  );

  Widget get _divider => const Divider(height: 1, indent: 52);

  String get _calendarName {
    for (final calendar in model.calendars) {
      if (calendar['id'] == model.settings.calendarIdentifier) {
        return '${calendar['name']} · ${calendar['source']}';
      }
    }
    return 'Календарь выбран';
  }

  String get _aiLabel {
    if (model.settings.profiles.isEmpty) return 'Не подключён';
    if (model.settings.selectedProfile == 'auto') {
      return 'Авто · ${model.settings.profiles.length}';
    }
    return model.settings.profiles
        .firstWhere(
          (profile) => profile.id == model.settings.selectedProfile,
          orElse: () => model.settings.profiles.first,
        )
        .name;
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool connected,
    required VoidCallback onTap,
  }) => ListTile(
    minTileHeight: 54,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    leading: Icon(icon, size: 20),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Icon(
      connected ? Icons.check_circle : Icons.chevron_right,
      color: connected ? const Color(0xff6d8f84) : null,
      size: 19,
    ),
    onTap: model.busy ? null : onTap,
  );

  Widget _utilityRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) => ListTile(
    minTileHeight: 46,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    leading: Icon(icon, size: 18),
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    trailing: const Icon(Icons.open_in_new, size: 16),
    onTap: onTap,
  );

  Future<void> _calendar(BuildContext context) async {
    await model.loadCalendar();
    if (!context.mounted || model.error != null || model.calendars.isEmpty) {
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Календарь'),
        children: model.calendars
            .map(
              (calendar) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, calendar['id']),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text('${calendar['name']} · ${calendar['source']}'),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      await model.saveSettings(
        (settings) => settings.copyWith(calendarIdentifier: selected),
      );
    }
  }

  Future<void> _telegram(BuildContext context) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => CredentialsDialog(
        title: 'Telegram',
        firstLabel: 'Токен бота',
        secondLabel: 'Ваш Chat ID',
        secondInitial: model.settings.telegramChat,
        keepExistingSecret: model.settings.telegramEnabled,
      ),
    );
    if (values == null) return;
    await model.run(() async {
      if (!RegExp(r'^\d+$').hasMatch(values[1])) {
        throw const FormatException('Нужен числовой Chat ID');
      }
      if (values[0].isNotEmpty) {
        if (!RegExp(r'^\d+:[A-Za-z0-9_-]+$').hasMatch(values[0])) {
          throw const FormatException('Проверьте токен бота');
        }
        await model.native.setSecret('telegram', values[0]);
      }
      await model.integrations.telegram('getMe', {});
      await model.repository.configure(
        (settings) => settings.copyWith(
          telegramChat: values[1],
          telegramEnabled: true,
          telegramOffset:
              values[0].isNotEmpty || values[1] != settings.telegramChat
              ? 0
              : settings.telegramOffset,
        ),
      );
      model.notice = 'Telegram подключён';
    });
  }

  Future<void> _todoist(BuildContext context) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => CredentialsDialog(
        title: 'Todoist',
        firstLabel: 'API-токен',
        keepExistingSecret: model.settings.todoistEnabled,
      ),
    );
    if (values == null || values[0].isEmpty) return;
    await model.run(() async {
      await model.native.setSecret('todoist', values[0]);
      await model.repository.configure(
        (settings) => settings.copyWith(todoistEnabled: true),
      );
      model.notice = 'Todoist подключён';
    });
  }
}
