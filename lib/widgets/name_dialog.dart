import 'package:flutter/material.dart';

/// Asks for a person's name (add or rename). Returns the trimmed name, or null if cancelled / empty.
Future<String?> showNameDialog(BuildContext context,
    {required String title, required String action, String initial = ''}) async {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(action)),
      ],
    ),
  );
  // not disposed here: the dialog's closing animation still uses it
  return name == null || name.isEmpty ? null : name;
}

/// Confirms deleting a person. Their items are kept and become unassigned.
Future<bool> confirmDeletePerson(BuildContext context, String name, {int items = 0, double amount = 0}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $name?'),
      content: Text(items == 0
          ? 'Nothing is assigned to $name.'
          : '$name has $items item${items == 1 ? '' : 's'} (€${amount.toStringAsFixed(2)}). '
              'They stay on the bill as unassigned, so you can give them to someone else.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ),
  );
  return ok ?? false;
}
