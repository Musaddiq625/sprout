import 'dart:io';

import 'package:flutter/material.dart';

import '../creature/creature_store.dart';
import '../key_constants.dart';

/// Every grass photo the creature has eaten — a local-only gallery.
/// Photos live in `docs/meals/`; nothing leaves the device.
class MealsPage extends StatefulWidget {
  const MealsPage({super.key, required this.store});

  final CreatureStore store;

  @override
  State<MealsPage> createState() => _MealsPageState();
}

class _MealsPageState extends State<MealsPage> {
  List<Map<String, Object?>> _meals = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.store.meals().then((m) {
      if (mounted) {
        setState(() {
          _meals = m;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memories')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _meals.isEmpty
              ? Center(
                  child: Text(
                    'No meals yet — feed it grass.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                )
              : GridView.builder(
                  key: KeyConstants.mealsGrid,
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _meals.length,
                  itemBuilder: (context, i) {
                    final meal = _meals[i];
                    final path = meal['path'] as String;
                    final at = DateTime.fromMillisecondsSinceEpoch(
                        meal['created_at'] as int);
                    return GestureDetector(
                      onTap: () => _showMeal(path, at),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.white12,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showMeal(String path, DateTime at) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Eaten ${_label(at)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
