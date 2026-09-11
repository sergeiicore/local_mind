import 'package:flutter/material.dart';

import '../../data/ai_service.dart';
import '../../domain/models.dart';
import '../app_model.dart';

class AiProfilesDialog extends StatelessWidget {
  const AiProfilesDialog({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final selected =
          model.settings.profiles.any(
            (profile) => profile.id == model.settings.selectedProfile,
          )
          ? model.settings.selectedProfile
          : 'auto';
      final hasCodex = model.settings.profiles.any(
        (profile) => profile.isCodex,
      );
      return AlertDialog(
        title: const Text('AI'),
        content: SizedBox(
          width: 390,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Исполнитель'),
                  items: [
                    const DropdownMenuItem(value: 'auto', child: Text('Авто')),
                    ...model.settings.profiles.map(
                      (profile) => DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: model.busy
                      ? null
                      : (value) => model.saveSettings(
                          (settings) =>
                              settings.copyWith(selectedProfile: value),
                        ),
                ),
                const SizedBox(height: 10),
                if (!hasCodex)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.terminal, size: 20),
                    title: const Text('Codex CLI'),
                    subtitle: const Text('Текущий вход'),
                    trailing: FilledButton(
                      onPressed: model.busy ? null : _connectCodex,
                      child: const Text('Подключить'),
                    ),
                  ),
                for (final profile in model.settings.profiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      profile.isCodex
                          ? Icons.terminal
                          : profile.isLocal
                          ? Icons.computer_outlined
                          : Icons.cloud_outlined,
                      size: 20,
                    ),
                    title: Text(profile.name),
                    subtitle: Text(
                      _profileSummary(profile),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Действия',
                      onSelected: (action) {
                        if (action == 'edit') _edit(context, profile);
                        if (action == 'remove') _remove(profile);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Изменить'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Облачные API'),
                  value: !model.settings.localOnly,
                  onChanged: model.busy
                      ? null
                      : (value) => model.saveSettings(
                          (settings) => settings.copyWith(localOnly: !value),
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: model.busy ? null : () => _edit(context),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('API / Ollama'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ],
      );
    },
  );

  Future<void> _connectCodex() => model.run(() async {
    final raw = await model.native.call<Map<dynamic, dynamic>>('codexStatus');
    if (raw?['installed'] != true) {
      throw const FormatException(
        'Codex CLI не найден. Сначала установите его и войдите в аккаунт.',
      );
    }
    if (model.settings.profiles.any((profile) => profile.isCodex)) return;
    final profile = AiProfile(
      id: newId(),
      name: 'Codex',
      endpoint: '',
      model: '',
      protocol: 'codex',
    );
    await model.repository.configure(
      (settings) =>
          settings.copyWith(profiles: [profile, ...settings.profiles]),
    );
    model.notice = 'Codex подключён';
  });

  Future<void> _edit(BuildContext context, [AiProfile? existing]) async {
    final result = await showDialog<ProfileDraft>(
      context: context,
      builder: (_) => existing?.isCodex == true
          ? CodexProfileDialog(profile: existing!)
          : ProfileDialog(profile: existing),
    );
    if (result == null) return;
    await model.run(() async {
      if (result.key.isNotEmpty) {
        await model.native.setSecret('ai.${result.profile.id}', result.key);
      }
      await model.repository.configure(
        (settings) => settings.copyWith(
          profiles: existing == null
              ? [...settings.profiles, result.profile]
              : settings.profiles
                    .map(
                      (profile) =>
                          profile.id == existing.id ? result.profile : profile,
                    )
                    .toList(),
        ),
      );
      model.notice = 'AI-профиль сохранён';
    });
  }

  Future<void> _remove(AiProfile profile) => model.run(() async {
    await model.native.setSecret('ai.${profile.id}', '');
    await model.repository.configure(
      (settings) => settings.copyWith(
        profiles: settings.profiles
            .where((candidate) => candidate.id != profile.id)
            .toList(),
        selectedProfile: settings.selectedProfile == profile.id
            ? 'auto'
            : settings.selectedProfile,
      ),
    );
    model.notice = 'AI-профиль удалён';
  });

  String _profileSummary(AiProfile profile) {
    if (!profile.isCodex) {
      return profile.model.isEmpty
          ? profile.providerLabel
          : '${profile.providerLabel} · ${profile.model}';
    }
    final model = profile.model.isEmpty ? 'стандартная модель' : profile.model;
    final effort = profile.reasoningEffort.isEmpty
        ? 'по умолчанию'
        : profile.reasoningEffort;
    return 'Codex · $model · $effort';
  }
}

class ProfileDraft {
  const ProfileDraft(this.profile, this.key);

  final AiProfile profile;
  final String key;
}

class CodexProfileDialog extends StatefulWidget {
  const CodexProfileDialog({super.key, required this.profile});

  final AiProfile profile;

  @override
  State<CodexProfileDialog> createState() => _CodexProfileDialogState();
}

class _CodexProfileDialogState extends State<CodexProfileDialog> {
  static const _efforts = ['', 'low', 'medium', 'high', 'xhigh'];

  late final aiModel = TextEditingController(text: widget.profile.model);
  late String effort = _efforts.contains(widget.profile.reasoningEffort)
      ? widget.profile.reasoningEffort
      : '';

  @override
  void dispose() {
    aiModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Codex'),
    content: SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: aiModel,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Модель Codex',
              hintText: 'Пусто — выбор Codex по умолчанию',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: effort,
            decoration: const InputDecoration(labelText: 'Уровень рассуждений'),
            items: const [
              DropdownMenuItem(value: '', child: Text('По умолчанию')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'xhigh', child: Text('Extra high')),
            ],
            onChanged: (value) => setState(() => effort = value ?? ''),
          ),
          const SizedBox(height: 10),
          Text(
            'Настройки применяются только к запросам через этот профиль.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );

  void _save() => Navigator.pop(
    context,
    ProfileDraft(
      AiProfile(
        id: widget.profile.id,
        name: widget.profile.name,
        endpoint: widget.profile.endpoint,
        model: aiModel.text.trim(),
        protocol: 'codex',
        reasoningEffort: effort,
        enabled: widget.profile.enabled,
      ),
      '',
    ),
  );
}

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key, this.profile});

  final AiProfile? profile;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final name = TextEditingController(
    text: widget.profile?.name ?? 'Ollama',
  );
  late final endpoint = TextEditingController(
    text: widget.profile?.endpoint ?? 'http://localhost:11434/v1',
  );
  late final aiModel = TextEditingController(text: widget.profile?.model ?? '');
  final apiKey = TextEditingController();
  late String provider = _initialProvider;
  late String protocol = widget.profile?.protocol ?? 'chat';
  String? error;

  String get _initialProvider {
    final profile = widget.profile;
    if (profile == null || profile.isLocal) return 'ollama';
    if (Uri.tryParse(profile.endpoint)?.host == 'api.openai.com') {
      return 'openai';
    }
    return 'custom';
  }

  @override
  void dispose() {
    name.dispose();
    endpoint.dispose();
    aiModel.dispose();
    apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.profile == null ? 'Добавить AI' : 'AI-профиль'),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: provider,
              decoration: const InputDecoration(labelText: 'Тип'),
              items: const [
                DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
                DropdownMenuItem(value: 'openai', child: Text('OpenAI API')),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text('Совместимый API'),
                ),
              ],
              onChanged: (value) => _selectProvider(value!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: aiModel,
              decoration: const InputDecoration(labelText: 'Модель'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: endpoint,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            if (provider == 'custom') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: protocol,
                decoration: const InputDecoration(labelText: 'Протокол'),
                items: const [
                  DropdownMenuItem(
                    value: 'chat',
                    child: Text('Chat Completions'),
                  ),
                  DropdownMenuItem(
                    value: 'responses',
                    child: Text('Responses'),
                  ),
                ],
                onChanged: (value) => setState(() => protocol = value!),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: apiKey,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'API-ключ'),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );

  void _selectProvider(String value) {
    setState(() {
      provider = value;
      if (value == 'ollama') {
        name.text = 'Ollama';
        endpoint.text = 'http://localhost:11434/v1';
        protocol = 'chat';
      } else if (value == 'openai') {
        name.text = 'OpenAI';
        endpoint.text = 'https://api.openai.com/v1';
        protocol = 'responses';
      }
    });
  }

  void _save() {
    try {
      if (name.text.trim().isEmpty || aiModel.text.trim().isEmpty) {
        throw const FormatException('Укажите название и модель');
      }
      final profile = AiProfile(
        id: widget.profile?.id ?? newId(),
        name: name.text.trim(),
        endpoint: endpoint.text.trim(),
        model: aiModel.text.trim(),
        protocol: protocol,
      );
      AiService.endpoint(profile);
      Navigator.pop(context, ProfileDraft(profile, apiKey.text.trim()));
    } on FormatException catch (exception) {
      setState(() => error = exception.message);
    }
  }
}
