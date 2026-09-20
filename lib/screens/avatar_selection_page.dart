import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class AvatarSelectionPage extends StatefulWidget {
  final VoidCallback onNext;
  final String gender;

  const AvatarSelectionPage({
    super.key,
    required this.onNext,
    required this.gender,
  });

  @override
  State<AvatarSelectionPage> createState() => _AvatarSelectionPageState();
}

class _AvatarSelectionPageState extends State<AvatarSelectionPage> {
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    final prefix = widget.gender == 'Female' ? 'female' : 'male';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        const Text(
          'Choose your',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppTheme.textGrey,
          ),
        ),
        const Text(
          'Avatar',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBlack,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Select a beautiful profile picture to represent you.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textGrey,
          ),
        ),
        const SizedBox(height: 30),

        // Grid
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              final avatarIndex = index + 1;
              final isSelected = _selectedIndex == avatarIndex;
              final assetPath = 'assets/avatars/${prefix}_$avatarIndex.png';

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = avatarIndex;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
                      width: 4,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                              blurRadius: 15,
                              spreadRadius: 5,
                            )
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: CircleAvatar(
                      backgroundImage: ResizeImage(AssetImage(assetPath), width: 200),
                      backgroundColor: AppTheme.inputBg,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Next button
        ElevatedButton(
          onPressed: () {
            context.read<AppState>().setAvatarIndex(_selectedIndex);
            widget.onNext();
          },
          child: const Text('Next'),
        ),
      ],
    );
  }
}
