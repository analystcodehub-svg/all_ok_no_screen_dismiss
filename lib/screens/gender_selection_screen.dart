import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'female_onboarding/female_onboarding_parent.dart';
import 'male_onboarding/male_onboarding_parent.dart';

class GenderSelectionScreen extends StatefulWidget {
  const GenderSelectionScreen({super.key});

  @override
  State<GenderSelectionScreen> createState() => _GenderSelectionScreenState();
}

class _GenderSelectionScreenState extends State<GenderSelectionScreen> {
  String _selectedGender = ''; // 'Male' or 'Female'

  void _onProceedPressed() {
    if (_selectedGender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your gender')),
      );
      return;
    }

    // Save gender in provider state
    final appState = context.read<AppState>();
    appState.setSelectedGender(_selectedGender);

    if (_selectedGender == 'Male') {
      // Navigate to Male Caller Onboarding Flow
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MaleOnboardingParent()),
      );
    } else {
      // Navigate to Female Onboarding Flow (Step 3)
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FemaleOnboardingParent()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No app bar so the user cannot navigate back to the OTP screen
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textGrey,
                    ),
                  ),
                  Text(
                    'Gender',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
              const Spacer(),

              // Gender Selection Options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Male Option
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGender = 'Male';
                      });
                    },
                    child: _buildGenderCard(
                      label: 'Male',
                      subtext: '',
                      avatarAsset: 'assets/male_avatar.png',
                      isSelected: _selectedGender == 'Male',
                    ),
                  ),

                  // Female Option
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGender = 'Female';
                      });
                    },
                    child: _buildGenderCard(
                      label: 'Female',
                      subtext: '(Audio verification needed)',
                      avatarAsset: 'assets/female_avatar.png',
                      isSelected: _selectedGender == 'Female',
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Action and Warning Footer
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Gender cannot be changed later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _selectedGender.isNotEmpty ? _onProceedPressed : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedGender.isNotEmpty
                          ? AppTheme.primaryBlue
                          : const Color(0xFFCCCCCC),
                    ),
                    child: const Text('Proceed'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderCard({
    required String label,
    required String subtext,
    required String avatarAsset,
    required bool isSelected,
  }) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 150,
              height: 170,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: AppTheme.inputBg,
                  backgroundImage: AssetImage(avatarAsset),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBlack,
          ),
        ),
        if (subtext.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtext,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textGrey,
            ),
          ),
        ],
      ],
    );
  }
}
