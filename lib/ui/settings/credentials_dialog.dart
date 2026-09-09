import 'package:flutter/material.dart';

class CredentialsDialog extends StatefulWidget {
  const CredentialsDialog({
    super.key,
    required this.title,
    required this.firstLabel,
    this.secondLabel,
    this.secondInitial = '',
    this.keepExistingSecret = false,
  });

  final String title;
  final String firstLabel;
  final String? secondLabel;
  final String secondInitial;
  final bool keepExistingSecret;

  @override
  State<CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<CredentialsDialog> {
  final first = TextEditingController();
  late final second = TextEditingController(text: widget.secondInitial);

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: first,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.firstLabel,
              hintText: widget.keepExistingSecret ? 'Оставить прежний' : null,
            ),
          ),
          if (widget.secondLabel != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: second,
              decoration: InputDecoration(labelText: widget.secondLabel),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, [first.text.trim(), second.text.trim()]),
        child: const Text('Подключить'),
      ),
    ],
  );
}
