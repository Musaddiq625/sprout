import 'package:flutter/material.dart';

import '../../key_constants.dart';

/// Which source the user picked for a photo.
enum PhotoSource { camera, gallery, testPack }

/// Bottom sheet that asks where the photo comes from.
class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Where\'s the grass?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: KeyConstants.cameraButton,
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            subtitle: const Text('Photograph it now'),
            onTap: () => Navigator.pop(context, PhotoSource.camera),
          ),
          ListTile(
            key: KeyConstants.galleryButton,
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            subtitle: const Text('Pick a photo you already took'),
            onTap: () => Navigator.pop(context, PhotoSource.gallery),
          ),
          ListTile(
            key: KeyConstants.testPackButton,
            leading: const Icon(Icons.eco),
            title: const Text('Test pack'),
            subtitle: const Text('Bundled grass photo — no camera needed'),
            onTap: () => Navigator.pop(context, PhotoSource.testPack),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
