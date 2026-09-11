class AiProfile {
  const AiProfile({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.model,
    this.protocol = 'chat',
    this.reasoningEffort = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String endpoint;
  final String model;
  final String protocol;

  /// Optional Codex reasoning level. An empty value keeps the CLI default.
  final String reasoningEffort;
  final bool enabled;

  bool get isCodex => protocol == 'codex';

  bool get isLocal =>
      isCodex ||
      const [
        'localhost',
        '127.0.0.1',
        '::1',
      ].contains(Uri.tryParse(endpoint)?.host);

  String get providerLabel {
    if (isCodex) return 'Текущий вход Codex';
    if (Uri.tryParse(endpoint)?.host == 'api.openai.com') return 'OpenAI API';
    if (isLocal) return 'Локальная модель';
    return 'Совместимый API';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'model': model,
    'protocol': protocol,
    'reasoningEffort': reasoningEffort,
    'enabled': enabled,
  };

  factory AiProfile.fromJson(Map<String, dynamic> json) => AiProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    endpoint: json['endpoint'] as String,
    model: json['model'] as String,
    protocol: json['protocol'] as String? ?? 'chat',
    reasoningEffort: json['reasoningEffort'] as String? ?? '',
    enabled: json['enabled'] != false,
  );
}
