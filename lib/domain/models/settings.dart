import 'ai_profile.dart';

class Settings {
  const Settings({
    this.vaultPath = '',
    this.profiles = const [],
    this.selectedProfile = 'auto',
    this.localOnly = true,
    this.calendarIdentifier = '',
    this.telegramChat = '',
    this.telegramEnabled = false,
    this.telegramOffset = 0,
    this.todoistEnabled = false,
  });

  final String vaultPath;
  final String selectedProfile;
  final String calendarIdentifier;
  final String telegramChat;
  final List<AiProfile> profiles;
  final bool localOnly;
  final bool telegramEnabled;
  final bool todoistEnabled;
  final int telegramOffset;

  Settings copyWith({
    String? vaultPath,
    List<AiProfile>? profiles,
    String? selectedProfile,
    bool? localOnly,
    String? calendarIdentifier,
    String? telegramChat,
    bool? telegramEnabled,
    int? telegramOffset,
    bool? todoistEnabled,
  }) => Settings(
    vaultPath: vaultPath ?? this.vaultPath,
    profiles: profiles ?? this.profiles,
    selectedProfile: selectedProfile ?? this.selectedProfile,
    localOnly: localOnly ?? this.localOnly,
    calendarIdentifier: calendarIdentifier ?? this.calendarIdentifier,
    telegramChat: telegramChat ?? this.telegramChat,
    telegramEnabled: telegramEnabled ?? this.telegramEnabled,
    telegramOffset: telegramOffset ?? this.telegramOffset,
    todoistEnabled: todoistEnabled ?? this.todoistEnabled,
  );

  Map<String, dynamic> toJson() => {
    'vaultPath': vaultPath,
    'profiles': profiles.map((e) => e.toJson()).toList(),
    'selectedProfile': selectedProfile,
    'localOnly': localOnly,
    'calendarIdentifier': calendarIdentifier,
    'telegramChat': telegramChat,
    'telegramEnabled': telegramEnabled,
    'telegramOffset': telegramOffset,
    'todoistEnabled': todoistEnabled,
  };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    vaultPath: json['vaultPath'] as String? ?? '',
    profiles: (json['profiles'] as List<dynamic>? ?? [])
        .map((e) => AiProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    selectedProfile: json['selectedProfile'] as String? ?? 'auto',
    localOnly: json['localOnly'] != false,
    calendarIdentifier: json['calendarIdentifier'] as String? ?? '',
    telegramChat: json['telegramChat'] as String? ?? '',
    telegramEnabled: json['telegramEnabled'] == true,
    telegramOffset: json['telegramOffset'] as int? ?? 0,
    todoistEnabled: json['todoistEnabled'] == true,
  );
}
