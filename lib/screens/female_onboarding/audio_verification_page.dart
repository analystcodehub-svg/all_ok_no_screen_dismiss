import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';
import '../main_navigation.dart';

class AudioVerificationPage extends StatefulWidget {
  const AudioVerificationPage({super.key});

  @override
  State<AudioVerificationPage> createState() => _AudioVerificationPageState();
}

class _AudioVerificationPageState extends State<AudioVerificationPage> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isFinished = false;
  int _secondsRecorded = 0;
  Timer? _timer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _secondsRecorded = 0;
    });
    _animationController.repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRecorded++;
      });
      // Stop recording automatically after 6 seconds for demo
      if (_secondsRecorded >= 15) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    _animationController.stop();
    setState(() {
      _isRecording = false;
      _isFinished = true;
    });
  }

  void _submit() async {
    // Update state
    final appState = context.read<AppState>();
    appState.setAudioVerified(true);

    final String expertId = appState.nickname.toLowerCase();
    if (expertId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('experts')
            .doc(expertId)
            .set({
          'nickname': appState.nickname,
          'mobileNumber': appState.mobileNumber,
          'age': 2026 - appState.birthYear,
          'pricePerMin': 5,
          'languages': appState.primaryLanguage,
          'rating': 4.8,
          'isOnline': false, // Offline by default when onboarded
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error saving expert profile at onboarding: $e');
      }
    }
    
    // Navigate to Female Expert Dashboard and clear history
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigation()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        // Title
        const Text(
          'Audio',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppTheme.textGrey,
          ),
        ),
        const Text(
          'Verification',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBlack,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Read the script below to verify your profile.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textGrey,
          ),
        ),
        const SizedBox(height: 30),

        // Script Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.inputBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.borderGrey,
              width: 1.0,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'READ THIS SCRIPT:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 16),
              Text(
                '“हेलो! मुझे नए लोगों से मिलना और उनके साथ मजेदार बातें करना बहुत पसंद है। जिंदगी में हँसना और मुस्कुराना सबसे ज़रूरी है। तो आइए, कुछ अच्छी बातें करते हैं!”',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textBlack,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const Spacer(),

        // Interaction Area
        Center(
          child: Column(
            children: [
              if (_isRecording) ...[
                Text(
                  'Recording... 0:${_secondsRecorded.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_isFinished) ...[
                const Text(
                  'Recording Completed! Check details.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Microphone button
              GestureDetector(
                onTap: () {
                  if (_isFinished) {
                    // Reset to try again
                    setState(() {
                      _isFinished = false;
                      _secondsRecorded = 0;
                    });
                  } else if (_isRecording) {
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    double scale = 1.0;
                    if (_isRecording) {
                      scale = 1.0 + (_animationController.value * 0.15);
                    }
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.redAccent : AppTheme.primaryBlue,
                          boxShadow: [
                            BoxShadow(
                              color: (_isRecording ? Colors.redAccent : AppTheme.primaryBlue)
                                  .withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isFinished
                              ? Icons.replay_rounded
                              : (_isRecording ? Icons.stop_rounded : Icons.mic_none_outlined),
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isFinished
                    ? 'Tap to re-record'
                    : (_isRecording ? 'Tap to stop recording' : 'Tap to start recording'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),

        // Safe Badge or Submit Button
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isFinished) ...[
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Submit & Proceed'),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: AppTheme.primaryBlue.withOpacity(0.6)),
                  const SizedBox(width: 6),
                  Text(
                    '100% Safe and Private',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
            ],
          ),
        ),
      ],
    );
  }
}
