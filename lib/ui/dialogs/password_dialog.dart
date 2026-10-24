// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<String?> showPasswordDialog(
  BuildContext context, {
  required bool saving,
  required String fileName,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(saving: saving, fileName: fileName),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.saving, required this.fileName});
  final bool saving;
  final String fileName;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    if (_controller.text.isEmpty) {
      setState(() => _error = l10n.passwordTooShort);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.passwordTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(fontSize: 12, color: Color(0xff647382)),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              controller: _controller,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.saving
                    ? l10n.passwordSaveLabel
                    : l10n.passwordOpenLabel,
                errorText: _error,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Argon2id + AES-256-GCM · MSP v2',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}

enum SaveDecision { save, discard, cancel }

Future<SaveDecision> showSaveChangesDialog(
  BuildContext context,
  String fileName,
) async {
  final l10n = AppLocalizations.of(context);
  final decision = await showDialog<SaveDecision>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.saveDialogTitle),
      content: Text(l10n.saveDialogMessage(fileName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(SaveDecision.cancel),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SaveDecision.discard),
          child: Text(l10n.dontSave),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(SaveDecision.save),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  return decision ?? SaveDecision.cancel;
}
