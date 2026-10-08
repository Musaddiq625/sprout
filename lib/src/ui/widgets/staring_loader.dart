import 'dart:async';

import 'package:flutter/material.dart';

/// Animated loading indicator for AI calls — eyes that stare and blink.
class StaringLoader extends StatefulWidget {
  const StaringLoader({super.key});

  @override
  State<StaringLoader> createState() => _StaringLoaderState();
}

class _StaringLoaderState extends State<StaringLoader> {
  bool _blink = false;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (mounted) setState(() => _blink = !_blink);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _blink ? '◉ ◉' : '– –',
          style: const TextStyle(fontSize: 28),
        ),
        const SizedBox(width: 12),
        Text(
          'Sprout is thinking…',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }
}
