import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../services/local_chat_database.dart';
import '../services/block_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class ActiveCallPage extends StatefulWidget {
  final String? callRoomId; // Supplied for receiver/expert, generated for caller
  final String receiverId;
  final String callerId;
  final String nickname;
  final bool isCaller;
  final double pricePerMin;
  final bool isFirstFreeCall;
  final CallService? preStartedCallService;
  final String? avatarUrl;
  final int avatarIndex;
  final VoidCallback? onCallEnded;
  final int? callerCoinBalance;
  final bool? callerHasUsedFreeCall;

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
    this.avatarUrl,
    this.avatarIndex = 1,
    this.onCallEnded,
    this.callerCoinBalance,
    this.callerHasUsedFreeCall,
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
  int? _callerCoinBalance;
  bool? _callerHasUsedFreeCall;

  @override
  void initState() {
    super.initState();
    _roomId = widget.callRoomId;
    _callService = widget.preStartedCallService ?? CallService();
    
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

      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

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
                _remoteRenderer.srcObject = stream;
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

      if (actualExpertId.isEmpty || actualCallerId.isEmpty || actualCallerId.contains(' ') || actualCallerId == 'Unknown Caller') {
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
        }
      }

      if (actualExpertId.isNotEmpty) {
        final expertDoc = await FirebaseFirestore.instance
            .collection('experts')
            .doc(actualExpertId)
            .get();
        if (expertDoc.exists) {
          final tier = expertDoc.data()?['tier'] as String? ?? 'bronze';
          if (mounted) {
            setState(() {
              _expertEarningRate = tier == 'silver' ? 1.6 : 1.0;
            });
          }
        }
      }

      if (actualCallerId.isNotEmpty) {
        final callerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(actualCallerId)
            .get();
        debugPrint('[_resolveRemoteData] callerDoc exists: ${callerDoc.exists}, data: ${callerDoc.data()}');
        if (callerDoc.exists) {
          final b = (callerDoc.data()?['coinBalance'] as num?)?.toInt() ?? 0;
          final f = callerDoc.data()?['freeCallUsed'] as bool? ?? true;
          debugPrint('[_resolveRemoteData] Setting balance: $b, freeUsed: $f');
          if (mounted) {
            setState(() {
              _callerCoinBalance = b;
              _callerHasUsedFreeCall = f;
            });
          }
        }
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
              _remoteRenderer.srcObject = stream;
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
    final myUid = appState.uid;
    appState.setHasUsedFreeCall(true);
    await FirebaseFirestore.instance.collection('users').doc(myUid).set({
      'hasUsedFreeCall': true,
    }, SetOptions(merge: true));
  }


  void _startCallTimer() {
    if (_timer != null && _timer!.isActive) return;
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
        final balance = context.read<AppState>().coinBalance;
        if (balance < (widget.pricePerMin * 10).toInt()) {
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

      // Deduct balances at the start of every minute (1s, 61s, 121s) after free period
      // Deduct balances at the start of every minute (1s, 61s, 121s) after free period
      if (_duration > 0 && (_duration - 1) % 60 == 0) {
        if (widget.isCaller) {
          if (widget.isFirstFreeCall && _duration <= 120) {
            // First 2 minutes are free, do not deduct wallet
          } else {
            final requiredCoins = (widget.pricePerMin * 10).toInt();
            final currentBalance = context.read<AppState>().coinBalance;
            
            // Check if they have enough balance for this new minute
            if (currentBalance < requiredCoins) {
              _triggerHangup();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call ended: Insufficient balance')),
              );
            } else {
              // Deduct for the upcoming minute
              context.read<AppState>().deductCoinBalance(requiredCoins);
            }
          }
        }
        // Expert earnings are credited at call end in _hangupLocal()
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
    
    _saveCallLog();
    
    // Sync Caller's Wallet Deduction to Firestore exactly once at the end
    if (widget.isCaller && _duration > 0) {
      int callMinutes = (_duration / 60).ceil();
      if (widget.isFirstFreeCall) {
        callMinutes = (callMinutes >= 2) ? (callMinutes - 2) : 0;
      }
      if (callMinutes > 0) {
        final coinsToDeduct = callMinutes * (widget.pricePerMin * 10).toInt();
        
        // We can just query by callerId (which is the uid for users)
        final callerUid = widget.callerId; 
        
        FirebaseFirestore.instance.collection('users').doc(callerUid).update({
          'coinBalance': FieldValue.increment(-coinsToDeduct),
        }).catchError((e) => debugPrint('Error syncing caller wallet deduction: $e'));
        
        debugPrint('Caller billed for $callMinutes mins: -$coinsToDeduct coins synced to Firestore');
      }
    }

    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
    if (!widget.isCaller) {
      if (_duration >= 50) {
        int callMinutes = _duration ~/ 60;
        if (_duration % 60 >= 50) {
          callMinutes += 1;
        }
        final earned = _expertEarningRate * callMinutes;
        
        _updateExpertStats(earned, _duration, 'hindi');
        debugPrint('Expert earned: ₹${earned.toStringAsFixed(2)} (${_duration}s at ₹$_expertEarningRate/min, billed as $callMinutes min)');
      } else if (_duration > 0) {
        // Female talked for less than 50 seconds
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
      final docRef = FirebaseFirestore.instance.collection('experts').doc(expertId);
      
      int minutesToAdd = seconds ~/ 60;
      if (seconds % 60 >= 50) {
        minutesToAdd += 1;
      }
      
      // 1. Direct Firestore Update using FieldValue.increment
      await docRef.set({
        'totalEarnings': FieldValue.increment(earned),
        'redeemableBalance': FieldValue.increment(earned),
        'totalTalkSeconds': FieldValue.increment(seconds),
        'totalTalktimeMinutes': FieldValue.increment(minutesToAdd),
      }, SetOptions(merge: true));

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

  Future<void> _saveCallLog() async {
    try {
      final status = _duration > 0 ? 'ended' : 'missed';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Use roomId to ensure consistent logId between caller and receiver, avoiding duplicate Firestore records
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

      // 1. Save locally for instant Recents tab loading
      await LocalChatDatabase.instance.saveCallLogLocally(logData);

      // 2. Save to Firestore for cross-device sync (Only caller writes to avoid duplicate writes)
      if (widget.isCaller) {
        await FirebaseFirestore.instance.collection('call_logs').doc(logId).set(logData);
      }
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
    final balance = _callerCoinBalance ?? widget.callerCoinBalance;
    final usedFree = _callerHasUsedFreeCall ?? widget.callerHasUsedFreeCall ?? true;
    
    // Expert (female) sees a countdown based on caller's maximum affordable minutes
    if (!widget.isCaller && balance != null) {
      int reqCoins = (widget.pricePerMin * 10).toInt();
      if (reqCoins <= 0) reqCoins = 1;
      
      int maxMins = balance ~/ reqCoins;
      if (usedFree == false) {
        maxMins += 2; // Add 2 free minutes if not used
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
              Align(
                alignment: Alignment.topRight,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onSelected: (value) async {
                    if (value == 'report') {
                      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      final reporterId = widget.isCaller ? widget.callerId : (widget.receiverId.isEmpty ? currentUid : widget.receiverId);
                      final reportedId = widget.isCaller ? widget.receiverId : widget.callerId;
                      await FirebaseFirestore.instance.collection('reports').add({
                        'reporterId': reporterId,
                        'reportedId': reportedId,
                        'reportedName': widget.nickname,
                        'reason': 'Inappropriate behavior on call',
                        'timestamp': FieldValue.serverTimestamp(),
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
                              builder: (_, val, __) {
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
