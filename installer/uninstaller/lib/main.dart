// SPDX-License-Identifier: GPL-3.0-only
/// Standalone MoeSketchpad uninstaller.
///
/// Launched by the Add/Remove Programs entry written at install time:
///
///     moesketchpad_uninstaller.exe --install-dir="C:\...\MoeSketchpad"
///
/// It reverses everything the installer did: the `.moesp` file association, the
/// desktop and Start menu shortcuts, the user PATH entry, the ARP registry key
/// and finally the installation directory itself.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'install_manifest.dart';
import 'installer_strings.dart';
import 'uninstaller.dart';
import 'window_chrome.dart';
import 'windows_window_manager.dart';

const _accent = Color(0xff386f9f);
const _canvasColor = Color(0xfff7f9fb);
const _inkStrong = Color(0xff243543);
const _inkSoft = Color(0xff64748a);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UninstallerApp(installDir: readInstallDir(args)));
}

/// Reads the target installation directory from `--install-dir=<path>`, falling
/// back to the standard per-user install location when it is not supplied.
String readInstallDir(List<String> args) {
  final explicit = args
      .where((arg) => arg.startsWith('--install-dir='))
      .map((arg) => arg.substring('--install-dir='.length))
      .where((value) => value.isNotEmpty && !value.contains('"'))
      .firstOrNull;
  if (explicit != null) return explicit;
  final local = Platform.environment['LOCALAPPDATA'];
  return [
    local ?? Platform.environment['USERPROFILE'] ?? '.',
    'Programs',
    'MoeSketchpad',
  ].join(Platform.pathSeparator);
}

class UninstallerApp extends StatelessWidget {
  const UninstallerApp({super.key, required this.installDir});

  final String installDir;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MoeSketchpad Uninstall',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _accent),
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: _canvasColor,
    ),
    home: UninstallPage(installDir: installDir),
  );
}

/// Which of the uninstaller screens is showing.
enum UninstallStyles { confirm, progress, done }

class UninstallPage extends StatefulWidget {
  const UninstallPage({super.key, required this.installDir});

  final String installDir;

  @override
  State<UninstallPage> createState() => _UninstallPageState();
}

class _UninstallPageState extends State<UninstallPage> {
  UninstallStyles _view = UninstallStyles.confirm;
  String _status = '';
  double _progress = 0;
  bool _started = false;
  Timer? _autoConfirmTimer;

  /// Language recorded at install time; falls back to the system language.
  String _language = 'en';

  InstallerStrings get _strings => InstallerStrings(_language);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    WindowsWindowManager.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final manifest = await InstallManifest.load(widget.installDir);
    if (!mounted) return;
    setState(() {
      _language = manifest?.languageCode ?? _systemLanguage();
    });
    // The confirm screen already spells out exactly what will be removed, so it
    // doubles as the confirmation prompt. Auto-advance after a short countdown
    // so an ARP launch completes hands-free while a user-present launch still
    // has time to press Cancel.
    _autoConfirmTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_started) _startUninstall();
    });
  }

  String _systemLanguage() {
    // Mirrors the installer: follow the system UI language when supported.
    final code = Platform.localeName.split(RegExp('[-_]')).first.toLowerCase();
    return InstallerStrings.supported.contains(code) ? code : 'en';
  }

  /// Begins removal. The confirm screen has already been dismissed by the time
  /// this runs, either through the countdown or the Uninstall button.
  void _startUninstall() {
    _autoConfirmTimer?.cancel();
    if (!mounted || _started) return;
    setState(() {
      _status = _strings.uninstallStatusRemoving;
      _started = true;
      _view = UninstallStyles.progress;
    });
    unawaited(_runUninstall());
  }

  Future<void> _runUninstall() async {
    final uninstaller = Uninstaller(
      (step) => switch (step) {
        UninstallStep.removingFiles => _strings.uninstallStatusRemoving,
        UninstallStep.removingShortcuts => _strings.uninstallStatusShortcuts,
        UninstallStep.removingAssociation =>
          _strings.uninstallStatusAssociation,
        UninstallStep.removingPath => _strings.uninstallStatusPath,
        UninstallStep.removingRegistry => _strings.uninstallStatusRegistry,
        UninstallStep.complete => _strings.uninstallComplete,
      },
      onStep: (event) {
        if (!mounted) return;
        setState(() {
          _status = event.status;
          _progress = event.progress;
          if (event.step == UninstallStep.complete) {
            _view = UninstallStyles.done;
          }
        });
      },
    );
    await uninstaller.run(widget.installDir);
    // Whatever is left (this executable, its DLLs and AOT snapshot) is still
    // locked. Show the completion screen briefly, then hand the residue to a
    // detached shell that finishes the job after this process exits.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      await Uninstaller.scheduleSelfErase(widget.installDir);
      await WindowsWindowManager.close();
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
            title: strings.uninstallWindowTitle,
            subtitle:
                '${strings.versionLabel} ${InstallerStrings.kInstallerVersion}'
                ' \u00b7 ${strings.authorLabel}',
          ),
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_view) {
                  UninstallStyles.confirm => _confirmView(strings),
                  UninstallStyles.progress => _progressView(strings),
                  UninstallStyles.done => _doneView(strings),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Initial screen: spells out what will be removed and auto-confirms after a
  /// short countdown (or immediately when the Uninstall button is pressed).
  Widget _confirmView(InstallerStrings strings) => SizedBox(
    key: const ValueKey('confirm'),
    width: 400,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.report_problem_rounded,
            size: 52,
            color: Color(0xffc9453d),
          ),
          const SizedBox(height: 18),
          Text(
            strings.uninstallHeading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: _inkStrong,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings.uninstallConfirmBody,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.5, color: _inkSoft),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xffeef2f6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.installDir,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _inkSoft),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.autoConfirmHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _inkSoft),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: WindowsWindowManager.close,
                  child: Text(strings.uninstallCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  autofocus: true,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffc9453d),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _startUninstall,
                  child: Text(strings.uninstallHeading),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _progressView(InstallerStrings strings) => SizedBox(
    key: const ValueKey('progress'),
    width: 380,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.uninstallingHeading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: _inkStrong,
            ),
          ),
          const SizedBox(height: 28),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _started ? _progress : null,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xffe2e9ef),
                  color: _accent,
                ),
              ),
              Text(
                strings.percent((_progress * 100).round()),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _inkStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _inkSoft),
          ),
        ],
      ),
    ),
  );

  Widget _doneView(InstallerStrings strings) => SizedBox(
    key: const ValueKey('done'),
    width: 380,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 52, color: _accent),
          const SizedBox(height: 18),
          Text(
            strings.uninstallCompleteHeading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: _inkStrong,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings.uninstallCompleteBody,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.5, color: _inkSoft),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: WindowsWindowManager.close,
              child: Text(strings.finish),
            ),
          ),
        ],
      ),
    ),
  );
}
