// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:moesketchpad_installer/install_manifest.dart';
import 'package:moesketchpad_installer/uninstall_page.dart';
import 'package:moesketchpad_installer/installer_strings.dart';
import 'package:moesketchpad_installer/package_archive.dart';
import 'package:moesketchpad_installer/window_chrome.dart';

/// Installer version reported in the custom caption bar.
const kInstallerVersion = '1.0.0';

/// Build number supplied at compile time by CI (defaults to 0 locally).
const kBuildNumber = int.fromEnvironment('MSP_BUILD_NUMBER', defaultValue: 0);

const _payloadAsset = 'assets/moesketchpad-windows.zip';

const _accent = Color(0xff386f9f);

/// Surface behind the installer content pane.
const _canvasColor = Color(0xfff7f9fb);

/// Brand rail gradient endpoints.
const _brandTop = Color(0xff22415c);
const _brandBottom = Color(0xff3a7aa8);

/// Text colors shared by the content pane.
const _inkStrong = Color(0xff243543);
const _inkSoft = Color(0xff64748a);

/// Broadcasts WM_SETTINGCHANGE so Explorer and newly launched shells notice the
/// updated user PATH without requiring the user to sign out.
const _broadcastEnvironmentScript = r'''
$signature = @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
$type = Add-Type -MemberDefinition $signature -Name EnvBroadcast -Namespace Moe -PassThru
$result = [UIntPtr]::Zero
[void]$type::SendMessageTimeout([IntPtr]65535, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
exit 0
''';

/// Encodes a PowerShell script as UTF-16LE base64 for `-EncodedCommand`, which
/// avoids all quoting hazards of passing the script through `-Command`.
String _encodePowerShell(String script) {
  final bytes = <int>[];
  for (final unit in script.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add((unit >> 8) & 0xff);
  }
  return base64.encode(bytes);
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final waitPid = _readWaitPid(args);
  final installDir = _readInstallDir(args);
  final uninstall = args.contains('--uninstall');
  if (uninstall) {
    runApp(UninstallerApp(installDir: installDir));
    return;
  }
  runApp(InstallerApp(waitPid: waitPid, installDir: installDir));
}

/// Reads the install directory for an uninstall invoked from Add/Remove
/// Programs. The ARP entry stores it in [UninstallString]; when absent, fall
/// back to the manifest-less default install location.
String _readInstallDir(List<String> args) {
  final explicit = args
      .where((arg) => arg.startsWith('--install-dir='))
      .map((arg) => arg.substring('--install-dir='.length))
      .where((value) => value.isNotEmpty && !value.contains('"'))
      .firstOrNull;
  if (explicit != null) return explicit;
  final local = Platform.environment['LOCALAPPDATA'];
  return p.join(
    local ?? Platform.environment['USERPROFILE'] ?? '.',
    'Programs',
    'MoeSketchpad',
  );
}

int? _readWaitPid(List<String> args) {
  final value = args
      .where((arg) => arg.startsWith('--wait-pid='))
      .map((arg) => int.tryParse(arg.substring('--wait-pid='.length)))
      .firstOrNull;
  return value != null && value > 0 ? value : null;
}

class InstallerApp extends StatelessWidget {
  const InstallerApp({super.key, this.waitPid, this.installDir});
  final int? waitPid;
  final String? installDir;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MoeSketchpad Setup',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _accent),
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xfff5f7fa),
    ),
    home: InstallerPage(waitPid: waitPid, installDir: installDir),
  );
}

enum _InstallStage { welcome, installing, complete, failed }

class InstallerPage extends StatefulWidget {
  const InstallerPage({super.key, this.waitPid, this.installDir});
  final int? waitPid;
  final String? installDir;

  @override
  State<InstallerPage> createState() => _InstallerPageState();
}

class _InstallerPageState extends State<InstallerPage> {
  late final TextEditingController _path;
  _InstallStage _stage = _InstallStage.welcome;
  double _progress = 0;

  /// Progress caption for the active stage, in the selected language.
  String _status = InstallerStrings('zh').statusReady;
  String? _error;
  bool _desktopShortcut = true;
  bool _startMenuShortcut = true;
  bool _launchAfterInstall = true;
  String _selectedLanguage = 'zh'; // zh or en
  String _selectedMoespMode = 'auto'; // auto or skip

  /// Copy table for the currently selected interface language.
  InstallerStrings get _strings => InstallerStrings(_selectedLanguage);

  @override
  void initState() {
    super.initState();
    // Follow the system UI language when it is one the installer speaks.
    final systemLanguage = Platform.localeName
        .split(RegExp('[-_]'))
        .first
        .toLowerCase();
    if (InstallerStrings.supported.contains(systemLanguage)) {
      _selectedLanguage = systemLanguage;
    }
    _path = TextEditingController(
      text:
          widget.installDir ??
          p.join(
            Platform.environment['LOCALAPPDATA'] ??
                Platform.environment['USERPROFILE'] ??
                Directory.systemTemp.path,
            'Programs',
            'MoeSketchpad',
          ),
    );
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final strings = _strings;
    final destination = p.normalize(_path.text.trim());
    if (destination.isEmpty ||
        p.basename(destination).toLowerCase() != 'moesketchpad') {
      setState(() {
        _error = strings.folderInvalid;
      });
      return;
    }
    setState(() {
      _stage = _InstallStage.installing;
      _error = null;
      _progress = 0.08;
      _status = strings.statusPreparing;
    });
    try {
      if (widget.waitPid case final pid?) {
        setState(() => _status = strings.statusWaiting);
        await _waitForProcess(pid);
      }
      final running = await Process.run('tasklist.exe', [
        '/FI',
        'IMAGENAME eq moesketchpad.exe',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (running.exitCode != 0) {
        throw StateError(strings.errorRunning);
      }
      if ((running.stdout as String).toLowerCase().contains(
        '"moesketchpad.exe"',
      )) {
        throw StateError(strings.errorCloseFirst);
      }

      setState(() {
        _progress = 0.2;
        _status = strings.statusVerifying;
      });
      final payload = await rootBundle.load(_payloadAsset);
      final archive = ZipDecoder().decodeBytes(payload.buffer.asUint8List());
      validateApplicationArchive(archive);
      final installDir = Directory(destination);
      await installDir.create(recursive: true);

      final entries = archive.files.where((file) => file.isFile).toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final path = safePackageDestination(installDir.path, entry.name);
        final file = File(path);
        await file.parent.create(recursive: true);
        final contents = entry.content as List<int>;
        await file.writeAsBytes(contents, flush: true);
        if (i % 8 == 0 || i == entries.length - 1) {
          setState(() {
            _progress = 0.25 + 0.65 * (i + 1) / entries.length;
            _status = strings.statusInstalling(i + 1, entries.length);
          });
        }
      }

      // Copy this running installer next to the app so the ARP uninstall entry
      // (UninstallString -> "<installer.exe>" --uninstall) has something to call.
      setState(() {
        _progress = 0.91;
        _status = strings.statusIntegration;
      });
      final self = File(Platform.resolvedExecutable);
      final target = File(
        p.join(installDir.path, 'moesketchpad_installer.exe'),
      );
      if (await self.exists() && self.path != target.path) {
        await self.copy(target.path);
      }

      await _registerIntegration(
        installDir.path,
        desktopShortcut: _desktopShortcut,
        startMenuShortcut: _startMenuShortcut,
        registerPath: _selectedMoespMode == 'auto',
      );
      setState(() {
        _progress = 1;
        _status = strings.statusComplete;
        _stage = _InstallStage.complete;
      });
      if (_launchAfterInstall) {
        await Process.start(
          p.join(installDir.path, 'moesketchpad.exe'),
          const [],
          mode: ProcessStartMode.detached,
          workingDirectory: installDir.path,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _InstallStage.failed;
        _status = strings.statusFailed;
        _error = '$error';
      });
    }
  }

  Future<void> _waitForProcess(int pid) async {
    final strings = _strings;
    for (var attempt = 0; attempt < 180; attempt++) {
      final result = await Process.run('tasklist.exe', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (result.exitCode != 0) {
        throw StateError(strings.errorWaitClose);
      }
      if (!(result.stdout as String).contains('"$pid"')) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException(strings.errorTimeout);
  }

  Future<void> _registerIntegration(
    String installDir, {
    required bool desktopShortcut,
    required bool startMenuShortcut,
    required bool registerPath,
  }) async {
    await _run('reg.exe', [
      'add',
      r'HKCU\Software\Classes\.moesp',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      'MoeSketchpad.Document',
      '/f',
    ]);
    await _run('reg.exe', [
      'add',
      r'HKCU\Software\Classes\.moesp',
      '/v',
      'Content Type',
      '/t',
      'REG_SZ',
      '/d',
      'application/x-moesketchpad',
      '/f',
    ]);
    await _run('reg.exe', [
      'add',
      r'HKCU\Software\Classes\MoeSketchpad.Document',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      'MoeSketchpad Geometry Document',
      '/f',
    ]);
    await _run('reg.exe', [
      'add',
      r'HKCU\Software\Classes\MoeSketchpad.Document\DefaultIcon',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      '"${p.join(installDir, 'if.ico')}",0',
      '/f',
    ]);
    await _run('reg.exe', [
      'add',
      r'HKCU\Software\Classes\MoeSketchpad.Document\shell\open\command',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      '"${p.join(installDir, 'moesketchpad.exe')}" "%1"',
      '/f',
    ]);

    if (registerPath) {
      final userPathResult = await Process.run('reg.exe', [
        'query',
        r'HKCU\Environment',
        '/v',
        'Path',
      ]);
      if (userPathResult.exitCode != 0 && userPathResult.exitCode != 1) {
        throw StateError(_strings.errorPathRead);
      }
      final existingPath = RegExp(
        r'^\s*Path\s+REG_\w+\s+(.*)$',
        multiLine: true,
      ).firstMatch(userPathResult.stdout as String)?.group(1);
      final pathEntries = (existingPath ?? '')
          .split(';')
          .where((entry) => entry.isNotEmpty);
      final alreadyRegistered = pathEntries.any(
        (entry) => p.equals(p.normalize(entry), p.normalize(installDir)),
      );
      if (!alreadyRegistered) {
        final newPath = [...pathEntries, installDir].join(';');
        await _run('reg.exe', [
          'add',
          r'HKCU\Environment',
          '/v',
          'Path',
          '/t',
          'REG_EXPAND_SZ',
          '/d',
          newPath,
          '/f',
        ]);
      }
      // Broadcast WM_SETTINGCHANGE so newly launched shells pick up the new
      // PATH without requiring a sign-out. Failures here are non-fatal.
      try {
        await _run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
          _encodePowerShell(_broadcastEnvironmentScript),
        ]);
      } on Object {
        // Non-fatal: PATH is stored even if the broadcast fails.
      }
    }

    final profile = Platform.environment['USERPROFILE'];
    final appData = Platform.environment['APPDATA'];
    if ((desktopShortcut && profile == null) ||
        (startMenuShortcut && appData == null)) {
      throw StateError(_strings.errorShortcutFolders);
    }
    final escapedInstall = installDir.replaceAll("'", "''");
    final shortcuts = <String>[
      if (desktopShortcut) p.join(profile!, 'Desktop', 'MoeSketchpad.lnk'),
      if (startMenuShortcut)
        p.join(
          appData!,
          'Microsoft',
          'Windows',
          'Start Menu',
          'Programs',
          'MoeSketchpad.lnk',
        ),
    ];
    for (final shortcut in shortcuts) {
      final escapedShortcut = shortcut.replaceAll("'", "''");
      final script =
          "\$shell = New-Object -ComObject WScript.Shell; "
          "\$link = \$shell.CreateShortcut('$escapedShortcut'); "
          "\$link.TargetPath = '$escapedInstall\\moesketchpad.exe'; "
          "\$link.WorkingDirectory = '$escapedInstall'; "
          "\$link.IconLocation = '$escapedInstall\\moesketchpad.exe,0'; "
          '\$link.Save()';
      await _run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]);
    }
    _registerUninstallEntry(installDir);
  }

  /// Registers the install in Add/Remove Programs so the app has a standard
  /// uninstall entry. The installer doubles as the uninstaller via the
  /// `--uninstall` flag.
  void _registerUninstallEntry(String installDir) {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MoeSketchpad';
    final exePath = p.join(installDir, 'moesketchpad_installer.exe');
    final escapedExe = exePath.replaceAll("'", "''");
    // Write the manifest so the uninstaller knows which options were chosen.
    InstallManifest.writeTo(
      installDir,
      InstallManifest(
        installDir: installDir,
        appVersion: kInstallerVersion,
        buildNumber: kBuildNumber,
        languageCode: _strings.languageCode,
        registeredPath: _selectedMoespMode == 'auto',
        desktopShortcut: _desktopShortcut,
        startMenuShortcut: _startMenuShortcut,
      ),
    );
    unawaited(
      _run('reg.exe', [
        'add',
        key,
        '/v',
        'DisplayName',
        '/t',
        'REG_SZ',
        '/d',
        'MoeSketchpad',
        '/f',
      ]),
    );
    unawaited(
      _run('reg.exe', [
        'add',
        key,
        '/v',
        'DisplayIcon',
        '/t',
        'REG_SZ',
        '/d',
        '"$escapedExe",0',
        '/f',
      ]),
    );
    _run('reg.exe', [
      'add',
      key,
      '/v',
      'InstallLocation',
      '/t',
      'REG_SZ',
      '/d',
      installDir,
      '/f',
    ]);
    _run('reg.exe', [
      'add',
      key,
      '/v',
      'UninstallString',
      '/t',
      'REG_SZ',
      '/d',
      '"$escapedExe" --uninstall --install-dir="$installDir"',
      '/f',
    ]);
    _run('reg.exe', [
      'add',
      key,
      '/v',
      'DisplayVersion',
      '/t',
      'REG_SZ',
      '/d',
      kInstallerVersion,
      '/f',
    ]);
    _run('reg.exe', [
      'add',
      key,
      '/v',
      'Publisher',
      '/t',
      'REG_SZ',
      '/d',
      _strings.authorLabel,
      '/f',
    ]);
  }

  Future<void> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  /// Opens the native Windows folder-browser dialog via the COM
  /// `Shell.Application` object and writes the chosen directory to [callback].
  /// The dialog always lets the caller pick a *parent* folder; the installer
  /// appends a `MoeSketchpad` suffix so the final install folder is always
  /// named correctly regardless of what the user selected.
  Future<void> _browseForFolder(
    BuildContext context,
    void Function(String path) callback,
  ) async {
    final script =
        "\$shell = New-Object -ComObject Shell.Application; "
        '\$folder = \$shell.BrowseForFolder(0, "选择安装到的文件夹 / Choose a folder"); '
        'if (\$folder) { Write-Output \$folder.Self.Path }';
    final encoded = _encodePowerShell(script);
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]);
    final output = (result.stdout as String?)?.trim();
    if (result.exitCode == 0 && output != null && output.isNotEmpty) {
      final chosen = p.join(output, 'MoeSketchpad');
      callback(p.normalize(chosen));
    } else if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_strings.folderPickError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    return Scaffold(
      backgroundColor: _canvasColor,
      body: Column(
        children: [
          // Frameless windows have no native caption, so Flutter draws one.
          WindowChrome(
            title: strings.windowTitle,
            subtitle:
                '${strings.versionLabel} $kInstallerVersion · ${strings.authorLabel}',
          ),
          Expanded(
            child: Row(
              children: [
                _brandPane(strings),
                Expanded(child: _contentPane(strings)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Left rail: product mark, tagline and license footer.
  Widget _brandPane(InstallerStrings strings) => SizedBox(
    width: 264,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandTop, _brandBottom],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.gesture_rounded,
                color: Colors.white,
                size: 29,
              ),
            ),
            const Spacer(),
            Text(
              strings.brandName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.brandLatin,
              style: const TextStyle(
                color: Color(0xffbcd9ec),
                fontSize: 11.5,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.brandTagline,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${strings.licenseLabel} · ${strings.authorLabel}',
                style: const TextStyle(
                  color: Color(0xffdceaf4),
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Right pane: the stage-specific content, on a plain surface.
  Widget _contentPane(InstallerStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 30, 36, 26),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _buildStage(strings),
    ),
  );

  Widget _buildStage(InstallerStrings strings) => switch (_stage) {
    _InstallStage.welcome => _welcome(strings),
    _InstallStage.installing => _installing(strings),
    _InstallStage.complete => _complete(strings),
    _InstallStage.failed => _failed(strings),
  };

  Widget _welcome(InstallerStrings strings) => Column(
    key: const ValueKey('welcome'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(strings.welcomeHeading, style: _titleStyle),
      const SizedBox(height: 8),
      Text(strings.welcomeSubtitle, style: _bodyStyle),
      const SizedBox(height: 24),
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(strings.folderLabel),
              const SizedBox(height: 7),
              TextField(
                controller: _path,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: strings.folderHint,
                  prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(strings.folderBrowse),
                  onPressed: () => _browseForFolder(
                    context,
                    (path) => setState(() => _path.text = path),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _fieldLabel(strings.languageLabel),
              const SizedBox(height: 7),
              DropdownButtonFormField<String>(
                initialValue: _selectedLanguage,
                style: const TextStyle(fontSize: 13, color: _inkStrong),
                decoration: _dropdownDecoration,
                items: [
                  for (final code in InstallerStrings.supported)
                    DropdownMenuItem(
                      value: code,
                      child: Text(InstallerStrings(code).languageName),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedLanguage = value;
                    // Refresh the progress caption into the new language so a
                    // mid-flow switch never leaves stale text behind.
                    _status = InstallerStrings(value).statusReady;
                  });
                },
              ),
              const SizedBox(height: 18),
              _fieldLabel(strings.moespLabel),
              const SizedBox(height: 7),
              DropdownButtonFormField<String>(
                initialValue: _selectedMoespMode,
                style: const TextStyle(fontSize: 13, color: _inkStrong),
                decoration: _dropdownDecoration,
                items: [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text(strings.moespAuto),
                  ),
                  DropdownMenuItem(
                    value: 'skip',
                    child: Text(strings.moespSkip),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _selectedMoespMode = value);
                },
              ),
              const SizedBox(height: 10),
              _option(strings.optionDesktop, _desktopShortcut, (v) {
                setState(() => _desktopShortcut = v);
              }),
              _option(strings.optionStartMenu, _startMenuShortcut, (v) {
                setState(() => _startMenuShortcut = v);
              }),
              _option(strings.optionLaunch, _launchAfterInstall, (v) {
                setState(() => _launchAfterInstall = v);
              }),
              if (_error != null) _errorBanner(_error!),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(strings.install),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _option(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (next) => onChanged(next ?? false),
      );

  Widget _installing(InstallerStrings strings) => Column(
    key: const ValueKey('installing'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(strings.installingHeading, style: _titleStyle),
      const Spacer(),
      Center(
        child: SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 118,
                height: 118,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: const Color(0xffe4eaf0),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gesture_rounded, size: 30, color: _accent),
                  const SizedBox(height: 4),
                  Text(
                    strings.percent((_progress * 100).round()),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _inkSoft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 26),
      Center(
        child: Text(
          _status,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _inkSoft),
        ),
      ),
      const Spacer(),
    ],
  );

  Widget _complete(InstallerStrings strings) => Column(
    key: const ValueKey('complete'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.check_circle_rounded,
        color: Color(0xff2d8b68),
        size: 46,
      ),
      const SizedBox(height: 16),
      Text(strings.completeHeading, style: _titleStyle),
      const SizedBox(height: 10),
      Text(strings.completeBody, style: _bodyStyle),
      const Spacer(),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => exit(0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Text(strings.finish),
          ),
        ),
      ),
    ],
  );

  Widget _failed(InstallerStrings strings) => Column(
    key: const ValueKey('failed'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.error_outline_rounded,
        color: Color(0xffbb4741),
        size: 46,
      ),
      const SizedBox(height: 16),
      Text(strings.failedHeading, style: _titleStyle),
      const SizedBox(height: 12),
      Expanded(
        child: SingleChildScrollView(
          child: SelectableText(
            _error ?? _status,
            style: const TextStyle(fontSize: 12.5, color: _inkSoft),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          TextButton(onPressed: () => exit(1), child: Text(strings.cancel)),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => setState(() => _stage = _InstallStage.welcome),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(strings.retry),
          ),
        ],
      ),
    ],
  );

  Widget _errorBanner(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: Color(0xffa53d39),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xffa53d39), fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: _inkStrong,
    ),
  );

  InputDecoration get _dropdownDecoration => const InputDecoration(
    border: OutlineInputBorder(),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  );

  TextStyle get _titleStyle => const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: _inkStrong,
  );

  TextStyle get _bodyStyle =>
      const TextStyle(fontSize: 13, color: _inkSoft, height: 1.55);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
