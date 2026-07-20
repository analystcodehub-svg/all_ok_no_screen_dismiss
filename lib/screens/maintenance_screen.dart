import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold that ignores back buttons and block pop
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgLight,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated or static maintenance icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.build_circle_outlined,
                      size: 100,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Main Title
                  const Text(
                    'We\'ll Be Right Back!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subtitle / Message
                  const Text(
                    'We are currently performing some scheduled maintenance to improve your experience.\n\nThe app will be back online shortly. Thank you for your patience!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Support Box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Need Urgent Help?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_outlined, size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            const Text(
                              'WhatsApp: +91 8987108642',
                              style: TextStyle(fontSize: 14, color: AppColors.textDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.email_outlined, size: 18, color: AppColors.primaryBlue),
                            const SizedBox(width: 8),
                            const Text(
                              'sajnireofficial@gmail.com',
                              style: TextStyle(fontSize: 14, color: AppColors.textDark),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
