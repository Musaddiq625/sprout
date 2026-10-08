import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai/model_manager.dart';
import '../key_constants.dart';

/// Download and manage the on-device Gemma model.
/// The app runs fake dialogue until this completes — download is
/// a first-run experience, not a gate.
class ModelManagerPage extends StatelessWidget {
  const ModelManagerPage({super.key, required this.manager});

  final ModelManager manager;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('The Model')),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sprout\'s brain lives on this phone.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Every line the creature says is generated locally by '
                'Gemma 4 E2B. No network, no API key, no data leaves '
                'your device.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              _ModelTile(
                status: manager.gemma,
                onDownload: () => manager.downloadGemma(),
                onImport: () => _importModel(context),
                onCancel: manager.cancelDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importModel(BuildContext context) async {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Select the .litertlm file',
    );
    final path = result?.path;
    if (path == null) return;
    await manager.importGemma(path);
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.status,
    required this.onDownload,
    required this.onImport,
    required this.onCancel,
  });

  final ModelStatus status;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusBadge(state: status.state),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmtBytes(status.expectedBytes)} • on-device',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),

            // Progress
            if (status.state == ModelState.downloading) ...[
              LinearProgressIndicator(
                key: KeyConstants.modelProgressBar,
                value: status.progress >= 0 ? status.progress : null,
              ),
              const SizedBox(height: 4),
              Text(
                status.progress >= 0
                    ? '${(status.progress * 100).round()}%'
                    : 'Importing…',
                style: Theme.of(context).textTheme.labelSmall,
                key: KeyConstants.modelStatusLabel,
              ),
            ],

            // Error
            if (status.state == ModelState.error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  status.error ?? 'Download failed',
                  style: const TextStyle(color: Colors.redAccent),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                if (status.state == ModelState.missing ||
                    status.state == ModelState.error) ...[
                  FilledButton.icon(
                    key: KeyConstants.downloadGemmaButton,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                    onPressed: onDownload,
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: KeyConstants.importModelButton,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import file'),
                    onPressed: onImport,
                  ),
                ],
                if (status.state == ModelState.downloading)
                  TextButton.icon(
                    key: KeyConstants.cancelDownloadButton,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    onPressed: onCancel,
                  ),
                if (status.state == ModelState.ready)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.greenAccent, size: 18),
                      SizedBox(width: 6),
                      Text('Sprout can speak for itself.'),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
    return '$bytes B';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final ModelState state;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(switch (state) {
        ModelState.ready => 'ready',
        ModelState.downloading => 'downloading',
        ModelState.error => 'error',
        _ => 'not installed',
      }),
      avatar: Icon(
        switch (state) {
          ModelState.ready => Icons.check_circle,
          ModelState.downloading => Icons.downloading,
          ModelState.error => Icons.error_outline,
          _ => Icons.cloud_off,
        },
        size: 14,
      ),
      labelStyle: const TextStyle(fontSize: 12),
      padding: EdgeInsets.zero,
    );
  }
}
