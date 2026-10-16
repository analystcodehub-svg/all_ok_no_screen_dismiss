import 'package:flutter/material.dart';

class LocalAvatarWidget extends StatelessWidget {
  final String uid;
  final String role; // 'expert' or 'user'
  final double radius;
  final String? avatarUrl;
  final int avatarIndex;

  const LocalAvatarWidget({
    super.key,
    required this.uid,
    required this.role,
    this.radius = 24.0,
    this.avatarUrl,
    this.avatarIndex = 1,
  });

  @override
  Widget build(BuildContext context) {
    String assetPath;
    
    ImageProvider imageProvider;

    final int targetDim = (radius * 2.5).toInt().clamp(48, 256);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      imageProvider = ResizeImage(
        NetworkImage(avatarUrl!),
        width: targetDim,
        height: targetDim,
        allowUpscaling: false,
      );
    } else {
      assetPath = role == 'expert' ? 'assets/avatars/female_$avatarIndex.png' : 'assets/avatars/male_$avatarIndex.png';
      imageProvider = ResizeImage(
        AssetImage(assetPath),
        width: targetDim,
        height: targetDim,
        allowUpscaling: false,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: imageProvider,
      backgroundColor: Colors.grey[200],
    );
  }
}
