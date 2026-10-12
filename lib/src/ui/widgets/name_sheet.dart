import 'package:flutter/material.dart';

import '../../key_constants.dart';

/// Bottom sheet to name (or rename) the creature.
/// Returns the entered name, or null if skipped/dismissed.
Future<String?> showNameSheet(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _NameSheet(current: current),
  );
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({this.current});

  final String? current;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current);

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.current == null
                ? 'It hatched. What is it called?'
                : 'Rename it',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: KeyConstants.nameField,
            controller: _ctrl,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Sprout',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip'),
              ),
              const Spacer(),
              FilledButton(
                key: KeyConstants.nameSaveButton,
                onPressed: _submit,
                child: const Text('That\'s it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
