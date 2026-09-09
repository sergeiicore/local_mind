import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';

class LocalRepository {
  LocalRepository(this.root);
  final Directory root;
  List<Entry> _entries = [];
  Settings settings = const Settings();
  Map<String, String> imported = {};
  List<Entry> get entries => List.unmodifiable(_entries);
  Future<void> _pending = Future.value();
  String? recoveryNotice;

  Future<void> load() async {
    await root.create(recursive: true);
    await Directory('${root.path}/Bridge/Incoming').create(recursive: true);
    final file = File('${root.path}/state.json');
    if (!await file.exists()) return;
    try {
      _decode(await file.readAsString());
    } catch (_) {
      final backup = File('${root.path}/state.backup.json');
      if (!await backup.exists()) {
        throw const FormatException(
          'Не удалось прочитать хранилище. Исходный файл сохранён.',
        );
      }
      _decode(await backup.readAsString());
      await file.copy(
        '${root.path}/state.damaged.${DateTime.now().millisecondsSinceEpoch}.json',
      );
      recoveryNotice =
          'Хранилище восстановлено из резервной копии; повреждённый файл сохранён рядом.';
    }
  }

  void _decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Неподдерживаемая версия хранилища');
    }
    final entries = (json['entries'] as List)
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final settings = Settings.fromJson(
      Map<String, dynamic>.from(json['settings'] as Map),
    );
    final imported = Map<String, String>.from(json['imported'] as Map? ?? {});
    _entries = entries;
    this.settings = settings;
    this.imported = imported;
  }

  Future<void> _transaction(void Function() change) {
    final operation = _pending.catchError((Object _) {}).then((_) async {
      final previous = _encode();
      change();
      try {
        await _persist(_encode());
      } catch (_) {
        _decode(previous);
        rethrow;
      }
    });
    _pending = operation;
    return operation;
  }

  String _encode() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'settings': settings.toJson(),
    'entries': _entries.map((e) => e.toJson()).toList(),
    'imported': imported,
  });
  Future<void> _persist(String value) async {
    final file = File('${root.path}/state.json');
    final temporary = File('${root.path}/state.next.json');
    await temporary.writeAsString(value, flush: true);
    if (await file.exists() && recoveryNotice == null) {
      await file.copy('${root.path}/state.backup.json');
    }
    await temporary.rename(file.path);
  }

  Future<void> add(Entry entry) => _transaction(() {
    if (!_entries.any((e) => e.id == entry.id)) _entries.insert(0, entry);
  });
  Future<void> update(String id, Entry Function(Entry) transform) =>
      _transaction(() {
        _entries = _entries.map((e) => e.id == id ? transform(e) : e).toList();
      });
  Future<void> configure(Settings Function(Settings) transform) =>
      _transaction(() => settings = transform(settings));

  Future<bool> importText({
    required String identity,
    required String text,
    required String source,
  }) async {
    if (text.trim().isEmpty || text.length > 100000) return false;
    var added = false;
    await _transaction(() {
      if (imported[identity] == text) return;
      _entries.insert(
        0,
        Entry(
          id: newId(),
          text: text.trim(),
          original: text,
          createdAt: DateTime.now(),
          source: source,
        ),
      );
      imported[identity] = text;
      added = true;
    });
    return added;
  }

  Future<int> importFolder(Directory directory, String source) async {
    if (!await directory.exists()) return 0;
    var count = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      if (await entity.length() > 100000) continue;
      final content = await entity.readAsString();
      if (await importText(
        identity: await entity.resolveSymbolicLinks(),
        text: content,
        source: source,
      )) {
        count++;
      }
    }
    return count;
  }

  Future<void> prepareVault(String path) async {
    final root = Directory(path);
    if (!await root.exists()) {
      throw const FileSystemException('Папка Obsidian недоступна');
    }
    for (final child in ['Incoming', 'Notes']) {
      final directory = Directory('$path/Local Mind/$child');
      await directory.create(recursive: true);
      final canonicalRoot = await root.resolveSymbolicLinks();
      if (!(await directory.resolveSymbolicLinks()).startsWith(
        '$canonicalRoot/',
      )) {
        throw const FileSystemException(
          'Папка Local Mind должна находиться внутри выбранного vault',
        );
      }
    }
  }

  Future<void> exportNotes() async {
    final path = settings.vaultPath;
    if (path.isEmpty) return;
    await prepareVault(path);
    for (final entry in entries.where((e) => !e.exported)) {
      final file = File('$path/Local Mind/Notes/${entry.id}.md');
      if (!await file.exists()) {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(markdown(entry), flush: true);
        await temp.rename(file.path);
      }
      await update(entry.id, (e) => e.copyWith(exported: true));
    }
  }

  static String markdown(Entry entry) {
    final buffer = StringBuffer(
      '---\nlocal_mind_id: ${entry.id}\ncreated: ${entry.createdAt.toIso8601String()}\nkind: ${entry.kind.name}\nsource: ${jsonEncode(entry.source)}\n',
    );
    if (entry.due != null) {
      buffer.writeln('due: ${localStamp(entry.due!.toLocal())}');
    }
    buffer.writeln('---\n');
    buffer.writeln(entry.text);
    if (entry.original.trim() != entry.text.trim()) {
      buffer.write('\n## Исходная запись\n\n${entry.original}\n');
    }
    return buffer.toString();
  }
}
