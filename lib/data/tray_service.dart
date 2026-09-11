import 'dart:async';

import 'package:nativeapi/nativeapi.dart' as nativeapi;

import 'native_service.dart';

/// Owns the nativeapi tray objects for the complete lifetime of the process.
class TrayService {
  TrayService._(this._native);

  static TrayService? _instance;

  final NativeService _native;
  nativeapi.TrayIcon? _tray;
  nativeapi.Menu? _menu;
  final List<nativeapi.MenuItem> _items = [];

  static bool get isInstalled => _instance != null;
  bool get isVisible => _tray?.isVisible() ?? false;
  int get menuItemCount => _menu?.itemCount ?? 0;

  static Future<void> install(NativeService native) async {
    final service = TrayService._(native);
    if (service._initialize()) _instance = service;
  }

  bool _initialize() {
    if (!nativeapi.TrayManager.instance.isSupported()) return false;
    final tray = nativeapi.TrayIcon.create();
    final menu = nativeapi.Menu.create();
    if (tray == null || menu == null) return false;

    _tray = tray;
    _menu = menu;
    tray.setTitle('LM');
    tray.setTooltip('Local Mind');
    tray.icon = nativeapi.ImageAsset.fromAsset(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png',
    );
    tray.setContextMenuTrigger(nativeapi.ContextMenuTrigger.rightClicked);
    tray.addListener((event) {
      if (event is nativeapi.TrayIconClickedEvent) {
        unawaited(_native.call<void>('showCapture'));
      }
    });

    _addItem(
      menu,
      'Открыть чат    ⌃⌥Space',
      () => _native.call<void>('showCapture'),
    );
    _addItem(
      menu,
      'Продиктовать    ⌃⌥⇧Space',
      () => _native.call<void>('showVoice'),
    );
    menu.addSeparator();
    _addItem(menu, 'Запускать при входе в Mac', _toggleLaunchAtLogin);
    _addItem(menu, 'Настройки', () => _native.call<void>('showSettings'));
    menu.addSeparator();
    _addItem(menu, 'Завершить Local Mind', () => _native.call<void>('quit'));
    tray.setContextMenu(menu);

    if (!tray.setVisible(true)) return false;
    unawaited(_refreshLaunchAtLogin());
    unawaited(_native.call<void>('disableFallbackTray'));
    return true;
  }

  void _addItem(
    nativeapi.Menu menu,
    String label,
    Future<void> Function() action,
  ) {
    final item = nativeapi.MenuItem.createWithLabelAndType(
      label,
      nativeapi.MenuItemType.normal,
    );
    if (item == null) return;
    item.addListener((event) {
      if (event is nativeapi.MenuItemClickedEvent) unawaited(action());
    });
    _items.add(item);
    menu.addItem(item);
  }

  Future<void> _toggleLaunchAtLogin() async {
    await _native.call<bool>('toggleLaunchAtLogin');
    await _refreshLaunchAtLogin();
  }

  Future<void> _refreshLaunchAtLogin() async {
    final enabled = await _native.call<bool>('launchAtLoginStatus') ?? false;
    final item = _items.length > 2 ? _items[2] : null;
    item?.state = enabled
        ? nativeapi.MenuItemState.checked
        : nativeapi.MenuItemState.unchecked;
  }
}
