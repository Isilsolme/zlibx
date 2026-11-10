import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Name + optional description form for a new booklist. Pops a record
/// `(title, description)`, or null when cancelled.
class CreateBooklistDialog extends StatefulWidget {
  const CreateBooklistDialog({super.key});

  @override
  State<CreateBooklistDialog> createState() => CreateBooklistDialogState();
}

class CreateBooklistDialogState extends State<CreateBooklistDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop((
      title: title,
      description: _descriptionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.createBooklist),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.booklistTitle,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.booklistDescriptionOptional,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _titleController.text.trim().isEmpty ? null : _submit,
          child: Text(l10n.create),
        ),
      ],
    );
  }
}
