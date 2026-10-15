import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../services/local_chat_database.dart';
import '../services/block_service.dart';
import '../services/user_database_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class ActiveCallPage extends StatefulWidget {
  final String? callRoomId; // Supplied for receiver/expert, generated for caller
  final String receiverId;
  final String callerId;
  final String nickname;
  final bool isCaller;
  final double pricePerMin;
  final CallService? preStartedCallService;
  final String? avatarUrl;
  final int avatarIndex;
  final VoidCallback? onCallEnded;
  final int? callerCoinBalance;

  const ActiveCallPage({
    super.key,
    this.callRoomId,
    required this.receiverId,
    required this.callerId,
    required this.nickname,
    required this.isCaller,
    required this.pricePerMin,
    this.preStartedCallService,
    this.avatarUrl,
    this.avatarIndex = 1,
    this.onCallEnded,
    this.callerCoinBalance,
  });

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  late final CallService _callService;
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
  int? _callerCoinBalance;
  StreamSubscription? _balanceSub;

  @override
  void initState() {
    super.initState();
    _roomId = widget.callRoomId;
    _callService = widget.preStartedCallService ?? CallService();
    
    if (widget.callerCoinBalance != null && widget.callerCoinBalance! > 0) {
      _callerCoinBalance = widget.callerCoinBalance;
    }

    if (!widget.isCaller) {
      _resolveRemoteData();
    }
    
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
        }
        return;
      }

      // Audio-only call: no RTCVideoRenderer surfaces are initialized
      // (saves ~100-200ms of GL texture setup). WebRTC plays remote audio
      // tracks automatically without a renderer.
      if (widget.preStartedCallService != null) {
        await _initCall();
        return;
      }

      if (!widget.isCaller) {
        await _callService.acceptCall(
          callRoomId: widget.callRoomId!,
          onRemoteStream: (stream) {
            if (mounted) {
              setState(() {
                _isConnected = true;
                _isSpeakerOn = true;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                Helper.setSpeakerphoneOn(true);
              });
              _ringingTimer?.cancel();
              _startCallTimer();
            }
          },
          onCallEnded: _hangupLocal,
        );

        if (mounted) {
          setState(() {
            if (_callService.remoteStream != null) {
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
          final maleCoins = mounted ? context.read<AppState>().coinBalance : null;
          final generatedRoomId = await _callService.startCall(
            expertId: widget.receiverId,
            callerId: widget.callerId,
            callerCoins: maleCoins,
            pricePerMin: widget.pricePerMin,
            onRemoteStream: (stream) {
              if (mounted) {
                setState(() {
                  _isConnected = true;
                  _isSpeakerOn = true;
                });
                Future.delayed(const Duration(milliseconds: 500), () {
                  Helper.setSpeakerphoneOn(true);
                });
                _ringingTimer?.cancel();
                _startCallTimer();
              }
            },
            onCallEnded: _hangupLocal,
          );
          if (mounted) {
            setState(() {
              _roomId = generatedRoomId;
            });
          } else {
            _callService.endCall(generatedRoomId);
          }
        } catch (e) {
          debugPrint('Error starting call: $e');
          _hangupLocal();
        }
      }
    } catch (e) {
      debugPrint('Error in _initRenderersAndCall: $e');
      _hangupLocal();
    }
  }

  Future<void> _resolveRemoteData() async {
    if (_tierResolved) return;
    _tierResolved = true;
    try {
      String actualExpertId = widget.receiverId;
      String actualCallerId = widget.callerId;

      debugPrint('[_resolveRemoteData] Initial - expert: $actualExpertId, caller: $actualCallerId');

      if (widget.callRoomId != null) {
        try {
          final FirebaseDatabase database = FirebaseDatabase.instanceFor(
            app: FirebaseDatabase.instance.app,
            databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
          );
          final callDoc = await database.ref('calls/${widget.callRoomId}').get();
          if (callDoc.exists) {
            final data = Map<String, dynamic>.from(callDoc.value as Map);
            actualCallerId = data['callerId'] ?? actualCallerId;
            actualExpertId = data['receiverId'] ?? actualExpertId;
            debugPrint('[_resolveRemoteData] Fetched from calls - expert: $actualExpertId, caller: $actualCallerId');
            if (data['callerCoins'] != null && _callerCoinBalance == null) {
              final c = (data['callerCoins'] as num).toInt();
              if (mounted) {
                setState(() {
                  _callerCoinBalance = c;
                });
              }
            }
          }
        } catch (e) {
          debugPrint('[_resolveRemoteData] Error fetching callDoc: $e');
        }
      }

      if (actualExpertId.isNotEmpty) {
        final expertData = await UserDatabaseService.instance.getExpert(actualExpertId);
        if (expertData != null) {
          final tier = expertData['tier'] as String? ?? 'bronze';
          if (mounted) {
            setState(() {
              _expertEarningRate = tier == 'silver' ? 1.6 : 1.0;
            });
          }
        }
      }

      if (actualCallerId.isNotEmpty) {
        if (_callerCoinBalance == null) {
          final callerData = await UserDatabaseService.instance.getUser(actualCallerId);
          debugPrint('[_resolveRemoteData] callerData exists: ${callerData != null}');
          if (callerData != null) {
            final b = (callerData['coinBalance'] as num?)?.toInt() ?? 0;
            debugPrint('[_resolveRemoteData] Setting balance: $b');
            if (mounted && _callerCoinBalance == null) {
              setState(() {
                _callerCoinBalance = b;
              });
            }
          }
        }

        // Listen for balance changes in real time (e.g. caller recharge during call)
        _balanceSub?.cancel();
        _balanceSub = UserDatabaseService.instance.usersRef
            .child(actualCallerId)
            .child('coinBalance')
            .onValue
            .listen((event) {
          if (event.snapshot.exists && event.snapshot.value != null) {
            final latestCoins = (event.snapshot.value as num).toInt();
            if (mounted && _callerCoinBalance != null && latestCoins > _callerCoinBalance!) {
              final added = latestCoins - _callerCoinBalance!;
              setState(() {
                _callerCoinBalance = (_callerCoinBalance ?? 0) + added;
              });
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error resolving remote data: $e');
    }
  }

  Future<void> _initCall() async {
    if (widget.preStartedCallService != null) {
      // Call is already pre-started by MatchingService
      _callService.updateListeners(
        onRemoteStream: (stream) {
          if (mounted) {
            setState(() {
              _isConnected = true;
              _isSpeakerOn = true;
            });
            Future.delayed(const Duration(milliseconds: 500), () {
              Helper.setSpeakerphoneOn(true);
            });
            _ringingTimer?.cancel();
            _startCallTimer();
          }
        },
        onCallEnded: _hangupLocal,
      );

      if (mounted) {
        setState(() {
          if (_callService.remoteStream != null) {
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
          callerCoins: context.read<AppState>().coinBalance,
          pricePerMin: widget.pricePerMin,
          onRemoteStream: (stream) {
            if (mounted) {
              setState(() {
                _isConnected = true;
                _isSpeakerOn = true;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                Helper.setSpeakerphoneOn(true);
              });
              _ringingTimer?.cancel();
              _startCallTimer();
            }
          },
          onCallEnded: _hangupLocal,
        );
        if (mounted) {
          setState(() {
            _roomId = generatedRoomId;
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
                _isConnected = true;
                _isSpeakerOn = true;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                Helper.setSpeakerphoneOn(true);
              });
              _startCallTimer();
            }
          },
          onCallEnded: _hangupLocal,
        );
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

  void _startCallTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _duration++;
      });

      // Female auto-hangup guard if duration exceeds caller's affordable time
      if (!widget.isCaller) {
        final balance = _callerCoinBalance ?? widget.callerCoinBalance ?? 30;
        int reqCoins = (widget.pricePerMin * 10).toInt();
        if (reqCoins <= 0) reqCoins = 30;
        int maxMins = balance ~/ reqCoins;
        if (maxMins <= 0 && balance > 0) maxMins = 1;
        int maxSecs = maxMins * 60;
        if (_duration > maxSecs && !_isHangingUp) {
          _triggerHangup();
          return;
        }
      }

      // Check and deduct balances on every first second of minute start (1s, 61s, 121s, 181s...)
      if (_duration > 0 && (_duration - 1) % 60 == 0) {
        if (widget.isCaller) {
          final requiredCoins = (widget.pricePerMin * 10).toInt() > 0
              ? (widget.pricePerMin * 10).toInt()
              : 30;
          final currentBalance = context.read<AppState>().coinBalance;
          
          if (currentBalance < requiredCoins) {
            _triggerHangup();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call ended: Insufficient balance')),
            );
            return;
          } else {
            context.read<AppState>().deductCoinBalance(requiredCoins);
            // Deduct new RTDB instantly via transaction
            UserDatabaseService.instance.deductUserCoins(widget.callerId, requiredCoins).then((success) {
              if (!success && mounted && !_isHangingUp) {
                _triggerHangup();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Call ended: Insufficient balance')),
                );
              }
            });
          }
          
          // Male incrementally logs the duration!
          _saveCallLogIncremental();
        }
      }
    });
  }

  void _triggerHangup() {
    if (_roomId != null) {
      _callService.endCall(_roomId!);
    }
    _hangupLocal();
  }

  void _hangupLocal() {
    if (_isHangingUp) return;
    _isHangingUp = true;
    
    // Clear CallKit Native Notifications
    FlutterCallkitIncoming.endAllCalls();
    
    // Unlock both parties safely (unlockUserFromCall checks experts collection internally)
    _callService.unlockUserFromCall(widget.callerId);
    _callService.unlockUserFromCall(widget.receiverId);
    
    _timer?.cancel();
    _ringingTimer?.cancel();
    
    final int finalDuration = _duration;
    final status = finalDuration > 0 ? 'ended' : 'missed';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final logId = 'log_${_roomId ?? timestamp}';
    
    final logData = {
      'logId': logId,
      'callerId': widget.callerId,
      'receiverId': widget.receiverId,
      'otherUserName': widget.nickname,
      'durationSeconds': finalDuration,
      'status': status,
      'timestamp': timestamp,
    };

    // ALWAYS save to local SQLite on this device immediately!
    LocalChatDatabase.instance.saveCallLogLocally(logData);

    // ALWAYS save final call log to RTDB (syncs to both caller & receiver)
    UserDatabaseService.instance.saveCallLog(
      logId,
      logData,
      isFinal: true,
    );

    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
    if (!widget.isCaller) {
      if (finalDuration >= 50) {
        int callMinutes = finalDuration ~/ 60;
        if (finalDuration % 60 >= 50) {
          callMinutes += 1;
        }
        final earned = _expertEarningRate * callMinutes;
        _updateExpertStats(earned, finalDuration, 'hindi');
        debugPrint('Expert earned: ₹${earned.toStringAsFixed(2)} (${finalDuration}s at ₹$_expertEarningRate/min, billed as $callMinutes min)');
      } else if (finalDuration > 0) {
        // Female talked for less than 50 seconds -> Earns Rs 0
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aapko Rs 1 earn karne ke liye kam se kam 50 seconds baat karni hogi.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
    
    if (mounted) {
      widget.onCallEnded?.call();
      Navigator.pop(context);
    }
  }

  Future<void> _updateExpertStats(double earned, int seconds, String language) async {
    try {
      String expertId = widget.receiverId;
      if (expertId.isEmpty) {
        expertId = FirebaseAuth.instance.currentUser?.uid ?? '';
      }
      if (expertId.isEmpty) return;
      int minutesToAdd = seconds ~/ 60;
      if (seconds % 60 >= 50) {
        minutesToAdd += 1;
      }
      // 1. Direct new RTDB Update using UserDatabaseService
      await UserDatabaseService.instance.incrementExpertStats(
        expertId,
        earned: earned,
        seconds: seconds,
        minutesToAdd: minutesToAdd,
      );

      // 2. Direct RTDB Update using ServerValue.increment
      try {
        final rtdb = FirebaseDatabase.instanceFor(
          app: FirebaseDatabase.instance.app,
          databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
        );
        
        // Update presence status node
        await rtdb.ref('status/$expertId').update({
          'totalTalkSeconds': ServerValue.increment(seconds),
        });
        
        // Safely update queue node if it exists using a transaction (100% ghost node proof)
        final lang = language.isNotEmpty ? language.toLowerCase() : 'hindi';
        final queueRef = rtdb.ref('queues/female_$lang/$expertId');
        
        await queueRef.runTransaction((Object? mutableData) {
          if (mutableData == null) {
            return Transaction.abort(); // Node doesn't exist, don't create ghost node
          }
          
          Map<Object?, Object?> data = Map<Object?, Object?>.from(mutableData as Map);
          int currentSeconds = (data['totalTalkSeconds'] as num?)?.toInt() ?? 0;
          data['totalTalkSeconds'] = currentSeconds + seconds;
          
          return Transaction.success(data);
        });
      } catch (rtdbError) {
        debugPrint('Error updating RTDB stats: $rtdbError');
      }
    } catch (e) {
      debugPrint('Error updating expert stats: $e');
    }
  }

  Future<void> _saveCallLogIncremental() async {
    try {
      final status = _duration > 0 ? 'ended' : 'missed';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final logId = 'log_${_roomId ?? timestamp}';
      
      final logData = {
        'logId': logId,
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'otherUserName': widget.nickname,
        'durationSeconds': _duration,
        'status': status,
        'timestamp': timestamp,
      };

      if (widget.isCaller) {
        // INCREMENTAL FIX: Continuously sync the exact duration to the database!
        await UserDatabaseService.instance.saveCallLog(
          logId,
          logData,
          isFinal: _isHangingUp,
        );
        
        // Only save to local SQLite at the very end of the call to avoid UI flickering
        if (_isHangingUp) {
          await LocalChatDatabase.instance.saveCallLogLocally(logData);
        }
      }
    } catch (e) {
      debugPrint('Error saving incremental call log: $e');
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
    // Expert (female) sees a countdown based strictly on caller's maximum affordable minutes
    if (!widget.isCaller) {
      final balance = _callerCoinBalance ?? widget.callerCoinBalance ?? 30;
      int reqCoins = (widget.pricePerMin * 10).toInt();
      if (reqCoins <= 0) reqCoins = 30;
      
      int maxMins = balance ~/ reqCoins;
      if (maxMins <= 0 && balance > 0) {
        maxMins = 1;
      }
      
      int maxSecs = maxMins * 60;
      int remaining = maxSecs - sec;
      if (remaining < 0) remaining = 0;
      
      final m = (remaining ~/ 60).toString().padLeft(2, '0');
      final s = (remaining % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    // Caller (male) sees a normal count-up timer
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringingTimer?.cancel();
    _balanceSub?.cancel();
    _callService.disposeCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _triggerHangup();
        return false;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onSelected: (value) async {
                    if (value == 'report') {
                      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      final reporterId = widget.isCaller ? widget.callerId : (widget.receiverId.isEmpty ? currentUid : widget.receiverId);
                      final reportedId = widget.isCaller ? widget.receiverId : widget.callerId;
                      await UserDatabaseService.instance.submitReport({
                        'reporterId': reporterId,
                        'reportedId': reportedId,
                        'reportedName': widget.nickname,
                        'reason': 'Inappropriate behavior on call',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User reported successfully. We will review this shortly.')),
                        );
                      }
                    } else if (value == 'block') {
                      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      final myId = widget.isCaller ? widget.callerId : (widget.receiverId.isEmpty ? currentUid : widget.receiverId);
                      final otherId = widget.isCaller ? widget.receiverId : widget.callerId;
                      await BlockService.instance.blockUser(myId, otherId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User blocked.')),
                        );
                        _triggerHangup();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Report User', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.black54, size: 20),
                          SizedBox(width: 8),
                          Text('Block & End Call'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Call header containing Profile details
              Column(
                children: [
                  const SizedBox(height: 10),
                  
                  // ── Male & Female Image Avatars ──────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Male Image Avatar
                      _buildImageAvatar(
                        imagePath: 'assets/male_avatar.png',
                        color: const Color(0xFF3B82F6),
                        label: 'Male',
                      ),

                      // Animated connection arrows
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.4, end: 1.0),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeInOut,
                              builder: (_, val, _) {
                                return Row(
                                  children: List.generate(3, (i) {
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF34D399).withValues(
                                          alpha: i == 0 ? val : i == 1 ? (val * 0.7) : (val * 0.4),
                                        ),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            const Icon(Icons.compare_arrows_rounded,
                                color: Color(0xFF34D399), size: 24),
                          ],
                        ),
                      ),

                      // Female Image Avatar
                      _buildImageAvatar(
                        imagePath: 'assets/female.jpeg',
                        color: const Color(0xFFEC4899),
                        label: 'Female',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Text(
                    widget.nickname,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isConnected ? 'Connected' : 'Calling...',
                    style: TextStyle(
                      color: _isConnected ? const Color(0xFF34D399) : Colors.white60,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isConnected) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'monospace',
                        letterSpacing: 2.0,
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
                        label: _isMuted ? 'Mic On' : 'Mic Off',
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
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.08),
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

  Widget _buildImageAvatar({
    required String imagePath,
    required Color color,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color.withValues(alpha: 0.8),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 3,
              ),
            ],
            image: DecorationImage(
              image: ResizeImage(AssetImage(imagePath), width: 300),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}
