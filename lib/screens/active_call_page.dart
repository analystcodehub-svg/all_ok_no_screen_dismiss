import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../widgets/local_avatar_widget.dart';

class ActiveCallPage extends StatefulWidget {
  final String? callRoomId; // Supplied for receiver/expert, generated for caller
  final String receiverId;
  final String callerId;
  final String nickname;
  final bool isCaller;
  final double pricePerMin;
  final bool isFirstFreeCall;
  final CallService? preStartedCallService;

  const ActiveCallPage({
    super.key,
    this.callRoomId,
    required this.receiverId,
    required this.callerId,
    required this.nickname,
    required this.isCaller,
    required this.pricePerMin,
    this.isFirstFreeCall = false,
    this.preStartedCallService,
  });

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final CallService _callService;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isConnected = false;
  String? _roomId;
  int _duration = 0;
  Timer? _timer;
  Timer? _ringingTimer;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isHangingUp = false;

  // Tier-based expert earning rate (resolved from Firestore on connect)
  double _expertEarningRate = 1.0; // default Bronze
  bool _tierResolved = false;

  @override
  void initState() {
    super.initState();
    _roomId = widget.callRoomId;
    _callService = widget.preStartedCallService ?? CallService();
    _initRenderersAndCall();

    if (widget.isCaller) {
      _ringingTimer = Timer(const Duration(seconds: 7), () {
        if (mounted && !_isConnected && !_isHangingUp) {
          _triggerHangup();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expert did not pick up. Please Try again.')),
          );
        }
      });
    }
  }

  Future<void> _initRenderersAndCall() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required for WebRTC audio calling.')),
          );
          Navigator.pop(context);
          return;
        }
      }
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      await _initCall();
    } catch (e) {
      debugPrint('Error during renderer initialization: $e');
    }
  }

  Future<void> _initCall() async {
    if (widget.preStartedCallService != null) {
      // Call is already pre-started by MatchingService
      _callService.updateListeners(
        onRemoteStream: (stream) {
          if (mounted) {
            setState(() {
              _remoteRenderer.srcObject = stream;
              _isConnected = true;
              _isSpeakerOn = true;
            });
            Future.delayed(const Duration(milliseconds: 500), () {
              Helper.setSpeakerphoneOn(true);
            });
            _ringingTimer?.cancel();
            _startCallTimer();
            if (!widget.isCaller) _resolveExpertTier();
          }
        },
        onCallEnded: _hangupLocal,
      );

      if (mounted) {
        setState(() {
          if (_callService.localStream != null) {
            _localRenderer.srcObject = _callService.localStream;
          }
          if (_callService.remoteStream != null) {
            _remoteRenderer.srcObject = _callService.remoteStream;
            _isConnected = true;
            _isSpeakerOn = true;
            _startCallTimer();
          }
        });
      }
      return;
    }

    if (widget.isCaller) {
      try {
        final generatedRoomId = await _callService.startCall(
          expertId: widget.receiverId,
          callerId: widget.callerId,
          onRemoteStream: (stream) {
            if (mounted) {
              setState(() {
                _remoteRenderer.srcObject = stream;
                _isConnected = true;
                _isSpeakerOn = true;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                Helper.setSpeakerphoneOn(true);
              });
              _ringingTimer?.cancel();
              _startCallTimer();
              if (!widget.isCaller) _resolveExpertTier();
            }
          },
          onCallEnded: _hangupLocal,
        );
        if (mounted) {
          setState(() {
            _roomId = generatedRoomId;
            if (_callService.localStream != null) {
              _localRenderer.srcObject = _callService.localStream;
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to place call: $e')),
          );
          Navigator.pop(context);
        }
      }
    } else {
      try {
        await _callService.acceptCall(
          callRoomId: _roomId!,
          onRemoteStream: (stream) {
            if (mounted) {
              setState(() {
                _remoteRenderer.srcObject = stream;
                _isConnected = true;
                _isSpeakerOn = true;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                Helper.setSpeakerphoneOn(true);
              });
              _startCallTimer();
              if (!widget.isCaller) _resolveExpertTier();
            }
          },
          onCallEnded: _hangupLocal,
        );
        if (mounted) {
          setState(() {
            if (_callService.localStream != null) {
              _localRenderer.srcObject = _callService.localStream;
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to connect incoming call: $e')),
          );
          Navigator.pop(context);
        }
      }
    }
  }

  void _markFreeCallUsed() async {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber;
    appState.setHasUsedFreeCall(true);
    await FirebaseFirestore.instance.collection('users').doc(mobile).set({
      'hasUsedFreeCall': true,
    }, SetOptions(merge: true));
  }

  Future<void> _resolveExpertTier() async {
    if (_tierResolved) return;
    _tierResolved = true;
    try {
      final expertId = widget.receiverId.toLowerCase();
      final expertSnap = await FirebaseFirestore.instance
          .collection('experts')
          .where('nickname', isEqualTo: expertId)
          .limit(1)
          .get();

      if (expertSnap.docs.isEmpty) return;

      final tier = expertSnap.docs.first.data()['tier'] as String? ?? 'bronze';
      if (mounted) {
        setState(() {
          _expertEarningRate = tier == 'silver' ? 1.6 : 1.0;
        });
      }
      debugPrint('Expert tier: $tier → ₹$_expertEarningRate/min');
    } catch (e) {
      debugPrint('Error resolving expert tier: $e');
    }
  }

  void _startCallTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _duration++;
      });

      if (_duration == 1 && widget.isCaller && widget.isFirstFreeCall) {
        _markFreeCallUsed();
      }

      // At exactly 2 min (120s): free period ends, check balance immediately
      if (_duration == 120 && widget.isCaller && widget.isFirstFreeCall) {
        final balance = context.read<AppState>().walletBalance;
        if (balance < widget.pricePerMin) {
          _triggerHangup();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Free 2 minutes over! Recharge to keep talking.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      // Deduct balances every 60 seconds (after free period)
      if (_duration > 0 && _duration % 60 == 0) {
        if (widget.isCaller) {
          if (widget.isFirstFreeCall && _duration <= 120) {
            // First 2 minutes are free, do not deduct wallet
          } else {
            context.read<AppState>().deductWalletBalance(widget.pricePerMin);
            final balance = context.read<AppState>().walletBalance;
            if (balance < widget.pricePerMin) {
              _triggerHangup();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call ended: Insufficient wallet balance')),
              );
            }
          }
        }
        // Expert earnings are credited at call end in _hangupLocal()
      }
    });
  }

  void _triggerHangup() async {
    if (_roomId != null) {
      await _callService.endCall(_roomId!);
    }
    _hangupLocal();
  }

  void _hangupLocal() {
    if (_isHangingUp) return;
    _isHangingUp = true;
    
    // Unlock both parties safely (unlockUserFromCall checks experts collection internally)
    _callService.unlockUserFromCall(widget.callerId);
    _callService.unlockUserFromCall(widget.receiverId);
    
    if (mounted) {
      _timer?.cancel();
      _ringingTimer?.cancel();
      
      if (widget.isCaller) {
        _saveCallLog();
      }
      // Credit expert earnings and update talk time at end of call (only if > 50 seconds)
      if (!widget.isCaller && _duration > 50) {
        final earned = _expertEarningRate * (_duration / 60.0);
        final appState = context.read<AppState>();
        appState.addEarnings(earned);
        debugPrint('Expert earned: ₹${earned.toStringAsFixed(2)} (${_duration}s at ₹$_expertEarningRate/min)');
        // Update all stats in Firestore
        _updateExpertStats(earned, _duration);
      }
      Navigator.pop(context);
    }
  }

  Future<void> _updateExpertStats(double earned, int seconds) async {
    try {
      final expertId = widget.receiverId.toLowerCase();
      if (expertId.isEmpty) return;
      final docRef = FirebaseFirestore.instance.collection('experts').doc(expertId);
      
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        final currentSeconds = (docSnap.data()?['totalTalkSeconds'] as num?)?.toInt() ?? 0;
        final newSeconds = currentSeconds + seconds;
        final newMinutes = newSeconds ~/ 60;
        
        await docRef.set({
          'totalEarnings': FieldValue.increment(earned),
          'redeemableBalance': FieldValue.increment(earned),
          'totalTalkSeconds': FieldValue.increment(seconds),
          'totalTalktimeMinutes': newMinutes,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating expert stats: $e');
    }
  }

  Future<void> _saveCallLog() async {
    try {
      final status = _duration > 0 ? 'ended' : 'missed';
      await FirebaseFirestore.instance.collection('call_logs').add({
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'durationSeconds': _duration,
        'status': status,
      });
    } catch (e) {
      debugPrint('Error saving call log: $e');
    }
  }

  void _toggleMute() {
    if (_callService.localStream != null) {
      final audioTracks = _callService.localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final newMuted = !_isMuted;
        for (var track in audioTracks) {
          track.enabled = !newMuted;
        }
        setState(() {
          _isMuted = newMuted;
        });
      }
    }
  }

  void _toggleSpeaker() {
    final newSpeaker = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(newSpeaker);
    setState(() {
      _isSpeakerOn = newSpeaker;
    });
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringingTimer?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _callService.disposeCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 20),
              
              // Call header containing Profile details
              Column(
                children: [
                  LocalAvatarWidget(
                    uid: widget.isCaller ? widget.receiverId : widget.callerId,
                    role: widget.isCaller ? 'expert' : 'user',
                    radius: 64,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.nickname,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected ? 'Connected' : 'Calling...',
                    style: TextStyle(
                      color: _isConnected ? Colors.greenAccent : Colors.white60,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isConnected) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),

              // Action controls for microphone & speaker outputs
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCallActionCircle(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        isActive: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildCallActionCircle(
                        icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Speaker',
                        isActive: _isSpeakerOn,
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                  
                  // End call button
                  GestureDetector(
                    onTap: _triggerHangup,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.call_end_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallActionCircle({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.08),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
