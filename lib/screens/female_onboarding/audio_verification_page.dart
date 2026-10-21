import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';
import '../main_navigation.dart';
import '../../services/user_database_service.dart';

class AudioVerificationPage extends StatefulWidget {
  const AudioVerificationPage({super.key});

  @override
  State<AudioVerificationPage> createState() => _AudioVerificationPageState();
}

class _AudioVerificationPageState extends State<AudioVerificationPage> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isFinished = false;
  bool _isUploading = false;
  int _secondsRecorded = 0;
  Timer? _timer;
  late AnimationController _animationController;
  final _audioRecorder = AudioRecorder();
  String? _recordedFilePath;

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
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/audio_verification_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        
        setState(() {
          _isRecording = true;
          _secondsRecorded = 0;
        });
        _animationController.repeat(reverse: true);

        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _secondsRecorded++;
          });
          // Stop recording automatically after 15 seconds
          if (_secondsRecorded >= 15) {
            _stopRecording();
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _animationController.stop();
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isFinished = true;
        _recordedFilePath = path;
      });
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  void _submit() async {
    if (_recordedFilePath == null) return;
    
    setState(() {
      _isUploading = true;
    });

    final appState = context.read<AppState>();
    final String expertId = appState.uid;
    String? audioUrl;

    if (expertId.isNotEmpty) {
      try {
        // 1. Upload to Firebase Storage
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('expert_audios')
            .child('$expertId.m4a');
        
        final File audioFile = File(_recordedFilePath!);
        await storageRef.putFile(audioFile);
        audioUrl = await storageRef.getDownloadURL();

        // 2. Save expert profile to NEW RTDB
        await UserDatabaseService.instance.setExpert(expertId, {
          'uid': expertId,
          'nickname': appState.nickname,
          'mobileNumber': appState.mobileNumber,
          'age': 2026 - appState.birthYear,
          'avatarIndex': appState.avatarIndex,
          'pricePerMin': 4, // System default
          'languages': appState.primaryLanguage,
          'rating': 4.8,
          'totalEarnings': 0.0,
          'redeemableBalance': 0.0,
          'totalTalktimeMinutes': 0,
          'totalTalkSeconds': 0,
          'audioVerificationUrl': audioUrl,
        });

        // 3. Keep audioVerificationUrl in Firestore as strictly requested
        await FirebaseFirestore.instance
            .collection('experts')
            .doc(expertId)
            .set({
          'audioVerificationUrl': audioUrl,
          'nickname': appState.nickname,
          'mobileNumber': appState.mobileNumber,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        appState.setAudioVerified(true);

        // Save referral info if present
        if (appState.enteredReferralCode.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('referrals').add({
              'referralCode': appState.enteredReferralCode,
              'referredUserId': expertId,
              'referredName': appState.nickname,
              'referredPhone': appState.mobileNumber,
              'joinedAt': FieldValue.serverTimestamp(),
              'status': 'joined',
            });
          } catch (e) {
            debugPrint('Failed to save referral: $e');
          }
        }
      } catch (e) {
        debugPrint('Error uploading audio or saving profile: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload audio. Please try again.')),
          );
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _isUploading = false;
      });
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
                                  .withValues(alpha: 0.4),
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
            if (_isUploading)
              const Center(child: CircularProgressIndicator())
            else if (_isFinished) ...[
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Submit & Proceed'),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: AppTheme.primaryBlue.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(
                    '100% Safe and Private',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey.withValues(alpha: 0.8),
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
