// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

import '../../build_info.dart';
import '../../l10n/app_localizations.dart';

Future<void> showAboutMoeSketchpad(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AboutDialog(),
  );
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  Future<void> _showAsset(
    BuildContext context,
    String path,
    String title,
  ) async {
    final text = await rootBundle.loadString(path);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 760,
          height: 560,
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 11, height: 1.45),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xfff0dbe4),
            child: Icon(Icons.gesture, color: Color(0xffa85375)),
          ),
          const SizedBox(width: 12),
          Text(l10n.appTitle),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.aboutVersion(BuildInfo.version, BuildInfo.buildNumber),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.aboutBuild(BuildInfo.buildDate, BuildInfo.commit),
                style: const TextStyle(fontSize: 12, color: Color(0xff61707f)),
              ),
              const SizedBox(height: 14),
              Text(l10n.aboutAuthor),
              const SizedBox(height: 4),
              SelectableText(BuildInfo.repository),
              SelectableText(BuildInfo.issues),
              const SizedBox(height: 14),
              Text(l10n.aboutLicense),
              SelectableText('SPDX-License-Identifier: ${BuildInfo.license}'),
              Text(
                l10n.aboutCopyright,
                style: const TextStyle(fontSize: 12, color: Color(0xff61707f)),
              ),
              const SizedBox(height: 10),
              Text(l10n.fileAssociation),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showAsset(context, 'COPYING', 'GPL-3.0'),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: Text(l10n.licenseFull),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showAsset(context, 'NOTICE', l10n.aboutNotice),
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: Text(l10n.aboutNotice),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  l10n.aboutNotice,
                  style: const TextStyle(fontSize: 13),
                ),
                children: const [
                  _ComponentLine('Flutter / Dart SDK', 'BSD-3-Clause'),
                  _ComponentLine('cryptography', 'Apache-2.0'),
                  _ComponentLine('archive', 'MIT'),
                  _ComponentLine('flutter_bloc / bloc', 'MIT'),
                  _ComponentLine('args', 'BSD-3-Clause'),
                  _ComponentLine('file_selector', 'BSD-3-Clause'),
                  _ComponentLine('window_manager', 'MIT'),
                  _ComponentLine('intl', 'BSD-3-Clause'),
                  _ComponentLine('path', 'BSD-3-Clause'),
                ],
              ),
              Text(
                moeSketchpadSystemPrompt(language: l10n.localeName),
                style: const TextStyle(fontSize: 10, color: Color(0xff788797)),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _ComponentLine extends StatelessWidget {
  const _ComponentLine(this.name, this.license);
  final String name;
  final String license;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(name, style: const TextStyle(fontSize: 12))),
        Text(
          license,
          style: const TextStyle(fontSize: 11, color: Color(0xff687888)),
        ),
      ],
    ),
  );
}
