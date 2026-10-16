import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

// The only file that imports device_info_plus: sign-in, never kid mode
// (test/auth/device_label_test.dart pins it).

/// The longest label a sign-in sends.
const kMaxSessionLabel = 64;

/// The coarse label a sign-in falls back to when the device cannot be
/// read: a platform class only. A platform the app does not ship on
/// sends none, and the session is named by its client kind.
String deviceLabelFor(TargetPlatform platform, {required bool web}) {
  if (web) return 'Navegador';
  return switch (platform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone ou iPad',
    _ => '',
  };
}

/// An Android device as its maker and model say ("Samsung SM-S911B",
/// "Google Pixel 9"): Android has no marketing name to read, and the
/// device name in Settings is the owner's own ("Celular da Ana"), never
/// sent. Empty when the model is unknown.
String androidDeviceLabel({
  required String manufacturer,
  required String model,
}) {
  final maker = _clean(manufacturer);
  final name = _clean(model);
  if (name.isEmpty) return '';
  if (maker.isEmpty || name.toLowerCase().startsWith(maker.toLowerCase())) {
    return _cap(name);
  }
  return _cap('${maker[0].toUpperCase()}${maker.substring(1)} $name');
}

/// An iPhone or iPad by the model name people know ("iPhone 15"), or by
/// its class ("iPhone") when the plugin does not know the model. Never
/// the device's name, which its owner sets ("iPhone de Ana").
String iosDeviceLabel({required String modelName, required String model}) {
  final known = _clean(modelName);
  if (known.isNotEmpty && known != 'Unknown device') return _cap(known);
  return _cap(_clean(model));
}

/// A browser and the system it runs on ("Chrome no Windows"), read from
/// the user-agent but never sending it: no version, no build, no model.
/// An unknown part is left out; both unknown leave "Navegador".
String webDeviceLabel({required BrowserName browser, String? userAgent}) {
  final agent = userAgent ?? '';
  // On iOS every browser is WebKit and reports Safari.
  final named = switch (agent) {
    _ when agent.contains('CriOS') => 'Chrome',
    _ when agent.contains('FxiOS') => 'Firefox',
    _ when agent.contains('EdgiOS') => 'Edge',
    _ => switch (browser) {
      BrowserName.chrome => 'Chrome',
      BrowserName.safari => 'Safari',
      BrowserName.firefox => 'Firefox',
      BrowserName.edge => 'Edge',
      BrowserName.opera => 'Opera',
      BrowserName.samsungInternet => 'Samsung Internet',
      BrowserName.msie => 'Internet Explorer',
      BrowserName.unknown => null,
    },
  };
  final system = switch (agent) {
    _ when agent.contains('iPhone') => 'iPhone',
    _ when agent.contains('iPad') => 'iPad',
    _ when agent.contains('Android') => 'Android',
    _ when agent.contains('CrOS') => 'ChromeOS',
    _ when agent.contains('Windows') => 'Windows',
    _ when agent.contains('Macintosh') || agent.contains('Mac OS X') => 'Mac',
    _ when agent.contains('Linux') => 'Linux',
    _ => null,
  };
  return switch ((named, system)) {
    (null, null) => 'Navegador',
    (final b?, null) => b,
    (final b, final s?) => '${b ?? 'Navegador'} no $s',
  };
}

String _clean(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

String _cap(String label) => label.runes.length <= kMaxSessionLabel
    ? label
    : String.fromCharCodes(label.runes.take(kMaxSessionLabel)).trimRight();

/// The platform reads a label is made from, behind a seam so tests
/// inject them. Only what names the model: never a serial, an ID, an OS
/// build or the name the owner gave the device.
abstract interface class DeviceReads {
  Future<({String manufacturer, String model})> android();
  Future<({String modelName, String model})> ios();
  Future<({BrowserName browser, String? userAgent})> browser();
}

/// [DeviceReads] from device_info_plus.
class PluginDeviceReads implements DeviceReads {
  PluginDeviceReads([DeviceInfoPlugin? plugin])
    : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  @override
  Future<({String manufacturer, String model})> android() async {
    final info = await _plugin.androidInfo;
    return (manufacturer: info.manufacturer, model: info.model);
  }

  @override
  Future<({String modelName, String model})> ios() async {
    final info = await _plugin.iosInfo;
    return (modelName: info.modelName, model: info.model);
  }

  @override
  Future<({BrowserName browser, String? userAgent})> browser() async {
    final info = await _plugin.webBrowserInfo;
    return (browser: info.browserName, userAgent: info.userAgent);
  }
}

/// Where a sign-in gets the label it sends.
abstract interface class DeviceLabelSource {
  Future<String> read();
}

/// This device's label, read once per run: the model on
/// Android and iOS, the browser and system on the web, and the coarse
/// [deviceLabelFor] when the read fails or names nothing.
class PlatformDeviceLabel implements DeviceLabelSource {
  PlatformDeviceLabel({
    DeviceReads? reads,
    this._platform,
    bool? web,
    this._patience = const Duration(seconds: 1),
  }) : _reads = reads ?? PluginDeviceReads(),
       _web = web ?? kIsWeb;

  final DeviceReads _reads;
  final TargetPlatform? _platform;
  final bool _web;

  /// The platform's answer, kept once it lands.
  String? _label;

  /// The read in flight. It outlives a sign-in that stopped waiting, so a
  /// cold start's slow first read still names the device next time; a
  /// failed read clears it to be tried again.
  Future<String>? _pending;

  @override
  Future<String> read() async {
    if (_label case final label?) return label;
    final platform = _platform ?? defaultTargetPlatform;
    final coarse = deviceLabelFor(platform, web: _web);
    final pending = _pending ??= _readPlatform(platform).then(
      (label) => _label = label.isEmpty ? coarse : label,
      onError: (Object _) {
        _pending = null;
        return coarse;
      },
    );
    try {
      return await pending.timeout(_patience);
    } on TimeoutException {
      return coarse;
    }
  }

  /// How long a sign-in waits on the platform before sending the coarse
  /// label instead.
  final Duration _patience;

  Future<String> _readPlatform(TargetPlatform platform) async {
    if (_web) {
      final b = await _reads.browser();
      return webDeviceLabel(browser: b.browser, userAgent: b.userAgent);
    }
    switch (platform) {
      case TargetPlatform.android:
        final a = await _reads.android();
        return androidDeviceLabel(manufacturer: a.manufacturer, model: a.model);
      case TargetPlatform.iOS:
        final i = await _reads.ios();
        return iosDeviceLabel(modelName: i.modelName, model: i.model);
      // Desktops are not shipped: no read, no label.
      case _:
        return '';
    }
  }
}
