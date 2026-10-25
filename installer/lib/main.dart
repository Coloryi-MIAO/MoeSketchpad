// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:moesketchpad_installer/package_archive.dart';

const _payloadAsset = 'assets/moesketchpad-windows.zip';
const _accent = Color(0xff386f9f);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final waitPid = _readWaitPid(args);
  final installDir = _readInstallDir(args);
  runApp(InstallerApp(waitPid: waitPid, installDir: installDir));
}

int? _readWaitPid(List<String> args) {
  final value = args
      .where((arg) => arg.startsWith('--wait-pid='))
      .map((arg) => int.tryParse(arg.substring('--wait-pid='.length)))
      .firstOrNull;
  return value != null && value > 0 ? value : null;
}

String? _readInstallDir(List<String> args) => args
    .where((arg) => arg.startsWith('--install-dir='))
    .map((arg) => arg.substring('--install-dir='.length))
    .where((value) => value.isNotEmpty && !value.contains('"'))
    .firstOrNull;

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
  String _status = 'Ready to install';
  String? _error;
  bool _desktopShortcut = true;
  bool _startMenuShortcut = true;
  bool _launchAfterInstall = true;

  @override
  void initState() {
    super.initState();
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
    final destination = p.normalize(_path.text.trim());
    if (destination.isEmpty ||
        p.basename(destination).toLowerCase() != 'moesketchpad') {
      setState(() {
        _error = 'Choose a folder whose final name is MoeSketchpad.';
      });
      return;
    }
    setState(() {
      _stage = _InstallStage.installing;
      _error = null;
      _progress = 0.08;
      _status = 'Preparing installation…';
    });
    try {
      if (widget.waitPid case final pid?) {
        setState(() => _status = 'Waiting for MoeSketchpad to close…');
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
        throw StateError('Could not check whether MoeSketchpad is running.');
      }
      if ((running.stdout as String).toLowerCase().contains(
        '"moesketchpad.exe"',
      )) {
        throw StateError('Close MoeSketchpad before installing or updating.');
      }

      setState(() {
        _progress = 0.2;
        _status = 'Verifying installation package…';
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
            _status = 'Installing files (${i + 1}/${entries.length})…';
          });
        }
      }

      setState(() {
        _progress = 0.93;
        _status = 'Creating shortcuts and file association…';
      });
      await _registerIntegration(
        installDir.path,
        desktopShortcut: _desktopShortcut,
        startMenuShortcut: _startMenuShortcut,
      );
      setState(() {
        _progress = 1;
        _status = 'Installation complete';
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
        _status = 'Installation failed';
        _error = '$error';
      });
    }
  }

  Future<void> _waitForProcess(int pid) async {
    for (var attempt = 0; attempt < 180; attempt++) {
      final result = await Process.run('tasklist.exe', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          'Could not wait for the running application to close.',
        );
      }
      if (!(result.stdout as String).contains('"$pid"')) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('MoeSketchpad did not close within three minutes.');
  }

  Future<void> _registerIntegration(
    String installDir, {
    required bool desktopShortcut,
    required bool startMenuShortcut,
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

    final userPathResult = await Process.run('reg.exe', [
      'query',
      r'HKCU\Environment',
      '/v',
      'Path',
    ]);
    if (userPathResult.exitCode != 0 && userPathResult.exitCode != 1) {
      throw StateError('Could not read the current user PATH.');
    }
    final existingPath = RegExp(
      r'^\s*Path\s+REG_\w+\s+(.*)$',
      multiLine: true,
    ).firstMatch(userPathResult.stdout as String)?.group(1);
    final pathEntries = (existingPath ?? '')
        .split(';')
        .where((entry) => entry.isNotEmpty);
    if (!pathEntries.any(
      (entry) => p.equals(p.normalize(entry), p.normalize(installDir)),
    )) {
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

    final profile = Platform.environment['USERPROFILE'];
    final appData = Platform.environment['APPDATA'];
    if ((desktopShortcut && profile == null) ||
        (startMenuShortcut && appData == null)) {
      throw StateError('Could not locate the current user shortcut folders.');
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 620),
        child: Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff244863), Color(0xff397aa7)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.gesture_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                        const Spacer(),
                        const Text(
                          '萌板',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'MOESKETCHPAD',
                          style: TextStyle(
                            color: Color(0xffcce4f2),
                            fontSize: 13,
                            letterSpacing: 2.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'A calm, precise space for ideas and geometry.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.84),
                            height: 1.5,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'GPL-3.0-only · Coloryi-MIAO',
                          style: TextStyle(
                            color: Color(0xffcce4f2),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildStage(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildStage() => switch (_stage) {
    _InstallStage.welcome => _welcome(),
    _InstallStage.installing => _installing(),
    _InstallStage.complete => _complete(),
    _InstallStage.failed => _failed(),
  };

  Widget _welcome() => Column(
    key: const ValueKey('welcome'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Install MoeSketchpad', style: _titleStyle),
      const SizedBox(height: 8),
      const Text(
        'Install the geometry workspace and its command-line tools for your Windows account.',
        style: TextStyle(color: Color(0xff667384), height: 1.45),
      ),
      const SizedBox(height: 26),
      const Text('Installation folder'),
      const SizedBox(height: 8),
      TextField(
        controller: _path,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.folder_outlined),
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 16),
      _option('Create a desktop shortcut', _desktopShortcut, (v) {
        setState(() => _desktopShortcut = v);
      }),
      _option('Add to Start menu', _startMenuShortcut, (v) {
        setState(() => _startMenuShortcut = v);
      }),
      _option('Launch after installation', _launchAfterInstall, (v) {
        setState(() => _launchAfterInstall = v);
      }),
      if (_error != null) _errorBanner(_error!),
      const Spacer(),
      Row(
        children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text('Install'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _option(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (next) => onChanged(next ?? false),
      );

  Widget _installing() => Column(
    key: const ValueKey('installing'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Setting up your workspace', style: _titleStyle),
      const Spacer(),
      Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xffe7edf2),
                ),
              ),
              Icon(Icons.gesture_rounded, size: 40, color: _accent),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Center(child: Text(_status)),
      const Spacer(),
    ],
  );

  Widget _complete() => Column(
    key: const ValueKey('complete'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.check_circle_rounded,
        color: Color(0xff2d8b68),
        size: 48,
      ),
      const SizedBox(height: 16),
      Text('You’re all set', style: _titleStyle),
      const SizedBox(height: 8),
      const Text(
        'MoeSketchpad and the moesp command are ready. Double-click a .moesp document to open it.',
        style: TextStyle(color: Color(0xff667384), height: 1.5),
      ),
      const Spacer(),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => exit(0),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text('Finish'),
          ),
        ),
      ),
    ],
  );

  Widget _failed() => Column(
    key: const ValueKey('failed'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.error_outline_rounded,
        color: Color(0xffbb4741),
        size: 48,
      ),
      const SizedBox(height: 16),
      Text('Could not finish setup', style: _titleStyle),
      const SizedBox(height: 12),
      Expanded(
        child: SingleChildScrollView(child: SelectableText(_error ?? _status)),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          TextButton(onPressed: () => exit(1), child: const Text('Cancel')),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => setState(() => _stage = _InstallStage.welcome),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ],
  );

  Widget _errorBanner(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xffa53d39), fontSize: 12),
    ),
  );

  TextStyle get _titleStyle => const TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w700,
    color: Color(0xff263847),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
