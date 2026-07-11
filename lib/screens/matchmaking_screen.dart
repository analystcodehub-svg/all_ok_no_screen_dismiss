import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/female_expert.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../services/matchmaking_service.dart';
import '../widgets/local_avatar_widget.dart';
import 'active_call_page.dart';

class MatchmakingScreen extends StatefulWidget {
  final FemaleExpert? requestedExpert;
  final bool isRandomMode;

  const MatchmakingScreen({
    super.key,
    this.requestedExpert,
    this.isRandomMode = false,
  });

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  final CallService _callService = CallService();
  late final MatchmakingService _matchingService;
  
  // ValueNotifiers to avoid setState rebuilds
  final ValueNotifier<String> _statusMessage = ValueNotifier<String>('Connecting...');
  final ValueNotifier<int> _ringingTimer = ValueNotifier<int>(0);
  final ValueNotifier<String?> _matchedExpertUidNotifier = ValueNotifier<String?>(null);
  Completer<bool>? _ringingCompleter;
  
  bool _isDisposed = false;
  bool _isSearchCancelled = false;
  Timer? _timer;
  StreamSubscription? _callStatusSub;

  @override
  void initState() {
    super.initState();
    _matchingService = MatchmakingService();
    
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startMatchmakingProcess();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isSearchCancelled = true;
    _radarController.dispose();
    _timer?.cancel();
    _callStatusSub?.cancel();
    _statusMessage.dispose();
    _ringingTimer.dispose();
    _matchedExpertUidNotifier.dispose();
    if (_ringingCompleter != null && !_ringingCompleter!.isCompleted) {
      _ringingCompleter!.complete(false);
    }
    super.dispose();
  }

  Future<void> _startMatchmakingProcess() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (_isDisposed || !mounted) return;

    final appState = context.read<AppState>();
    final String callerUid = appState.mobileNumber.isNotEmpty 
        ? appState.mobileNumber 
        : (appState.nickname.isNotEmpty ? appState.uid : 'caller_1');
    final String preferredLanguage = appState.primaryLanguage;
    final hasUsedFreeCall = appState.hasUsedFreeCall;

    String? matchedExpertUid;

    // Direct Call Mode
    if (!widget.isRandomMode && widget.requestedExpert != null) {
      _statusMessage.value = 'Checking availability for ${widget.requestedExpert!.nickname}...';
      matchedExpertUid = widget.requestedExpert!.id;
      
      bool isLocked = await _matchingService.lockExpertForCall(matchedExpertUid, callerUid);
      if (!isLocked) {
        if (!_isDisposed && mounted) {
          _statusMessage.value = '${widget.requestedExpert!.nickname} is busy. Finding another expert...';
          await Future.delayed(const Duration(seconds: 1)); // brief pause for UI
          
          if (!_isDisposed && !_isSearchCancelled) {
            matchedExpertUid = await _matchingService.findAndLockExpert(callerUid, 'female', preferredLanguage);
          } else {
            return;
          }
        } else {
          return;
        }
      }
    } 
    // Random Matchmaking Mode
    else {
      _statusMessage.value = 'Finding Expert...';
      matchedExpertUid = await _matchingService.findAndLockExpert(callerUid, 'female', preferredLanguage);

      if (_isDisposed || _isSearchCancelled) {
        if (matchedExpertUid != null) {
          await _matchingService.unlockExpert(matchedExpertUid);
        }
        return;
      }

      if (matchedExpertUid == null) {
        _statusMessage.value = 'No experts available right now. Please try again.';
        if (!_isDisposed && mounted) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
          }
        }
        return;
      }
    }

    if (matchedExpertUid == null) {
      _statusMessage.value = 'No experts available right now. Please try again.';
      if (!_isDisposed && mounted) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      }
      return;
    }

    // Update UI to show the expert's avatar
    _matchedExpertUidNotifier.value = matchedExpertUid;

    // WE HAVE A LOCKED EXPERT. Start Ringing process!
    _statusMessage.value = 'Ringing...';


    try {
      final callRoomId = await _callService.startCall(
        expertId: matchedExpertUid,
        callerId: callerUid,
        onRemoteStream: (stream) {},
        onCallEnded: () {},
      );

      if (_isDisposed || _isSearchCancelled) {
        await _callService.endCall(callRoomId);
        await _matchingService.unlockExpert(matchedExpertUid);
        return;
      }

      // 2. Start 15-second strict UI Timer
      _ringingTimer.value = 15;
      
      _ringingCompleter = Completer<bool>();
      
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (_ringingTimer.value > 0) {
          _ringingTimer.value--;
        } else {
          timer.cancel();
          if (!_ringingCompleter!.isCompleted) _ringingCompleter!.complete(false); // Timeout failed
        }
      });

      // 3. Listen to RTDB for expert answer ('connected' status)
      final db = FirebaseDatabase.instanceFor(
        app: FirebaseDatabase.instance.app,
        databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
      );
      
      _callStatusSub = db.ref('calls/$callRoomId/status').onValue.listen((event) {
        if (event.snapshot.value == 'connected') {
          if (!_ringingCompleter!.isCompleted) _ringingCompleter!.complete(true); // Success
        } else if (event.snapshot.value == 'ended') {
          if (!_ringingCompleter!.isCompleted) _ringingCompleter!.complete(false); // Rejected/Ended
        }
      });

      // Await answer or timeout
      bool expertAnswered = await _ringingCompleter!.future;

      _timer?.cancel();
      await _callStatusSub?.cancel();

      if (_isDisposed || _isSearchCancelled) {
        await _callService.endCall(callRoomId);
        await _matchingService.unlockExpert(matchedExpertUid);
        return;
      }

      if (expertAnswered) {
        // SUCCESS: Proceed with WebRTC stream
        final doc = await FirebaseFirestore.instance.collection('experts').doc(matchedExpertUid).get();
        
        String nickname = widget.requestedExpert?.nickname ?? matchedExpertUid.toUpperCase();
        double pricePerMin = widget.requestedExpert?.pricePerMin.toDouble() ?? 5.0;

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          nickname = data['nickname'] ?? nickname;
          pricePerMin = (data['pricePerMin'] as num?)?.toDouble() ?? 5.0;
        }

        if (!_isDisposed && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveCallPage(
                callRoomId: callRoomId,
                receiverId: matchedExpertUid ?? '', // We know it's not null here
                callerId: callerUid,
                nickname: nickname,
                pricePerMin: pricePerMin,
                isCaller: true,
                preStartedCallService: _callService,
                isFirstFreeCall: !hasUsedFreeCall,
              ),
            ),
          );
        }
      } else {
        // TIMEOUT OR REJECTED
        await _callService.endCall(callRoomId);
        await _matchingService.unlockExpert(matchedExpertUid);
        
        if (!_isDisposed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expert is busy, please try later.')),
          );
          Navigator.pop(context);
        }
      }

    } catch (e) {
      await _matchingService.unlockExpert(matchedExpertUid);
      if (!_isDisposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
        Navigator.pop(context);
      }
    }
  }

  void _cancelSearch() {
    _isSearchCancelled = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Dark slate
              Color(0xFF1E1B4B), // Deep indigo
              Color(0xFF0F172A), // Dark slate
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
          children: [
            const Spacer(),
            
            // Dynamic UI: Radar when searching, Avatars when ringing
            ValueListenableBuilder<String?>(
              valueListenable: _matchedExpertUidNotifier,
              builder: (context, matchedUid, child) {
                if (matchedUid == null) {
                  return _buildSearchingRadar();
                } else {
                  return _buildRingingAvatars(matchedUid);
                }
              },
            ),
            
            const Spacer(),
            
            // Status Text (Rebuilt efficiently via ValueListenableBuilder)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ValueListenableBuilder<String>(
                valueListenable: _statusMessage,
                builder: (context, statusMsg, child) {
                  return Text(
                    statusMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      height: 1.4,
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // 15-Second Timer Countdown (Only visible when ringing)
            ValueListenableBuilder<int>(
              valueListenable: _ringingTimer,
              builder: (context, timerValue, child) {
                if (timerValue > 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF43F5E).withValues(alpha: 0.1),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        '00:${timerValue.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xFFF43F5E),
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            const SizedBox(height: 60),
            
            // Cancel Button
            GestureDetector(
              onTap: _cancelSearch,
              child: Container(
                margin: const EdgeInsets.only(bottom: 40),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.15),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSearchingRadar() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding rings
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (index) {
                  final delay = index * 0.33;
                  double progress = (_radarController.value + delay) % 1.0;
                  return Transform.scale(
                    scale: 1.0 + (progress * 2.5),
                    child: Opacity(
                      opacity: (1.0 - progress).clamp(0.0, 1.0),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF43F5E), // Rose accent
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          
          // Revolving (Orbiting) Avatars
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(4, (index) {
                  // Orbit angle over time. 
                  // Multiply by 2 * PI for full rotation, add offset based on index.
                  double angle = (_radarController.value * 2 * math.pi) + (index * math.pi / 2);
                  // Dynamic radius moving outward then looping
                  double radius = 60.0 + ((_radarController.value + index * 0.25) % 1.0) * 60.0;
                  
                  return Transform.translate(
                    offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
                    child: Opacity(
                      // Fade out as they get further away
                      opacity: (1.0 - ((radius - 60) / 60)).clamp(0.0, 1.0),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundImage: AssetImage('assets/avatars/female_${index + 1}.png'),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  );
                }),
              );
            },
          ),

          // Center Avatar (Slower Spinner)
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              // Cycle through 6 avatars slowly (2 times per radar cycle instead of 30)
              int avatarIndex = ((_radarController.value * 4).toInt() % 6) + 1;
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF43F5E),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF43F5E).withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: AssetImage('assets/avatars/female_$avatarIndex.png'),
                  backgroundColor: Colors.white,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRingingAvatars(String expertUid) {
    String nickname = widget.requestedExpert?.nickname ?? 'Expert';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing Avatar
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ripple
                  Transform.scale(
                    scale: 1.0 + (_radarController.value * 0.5),
                    child: Opacity(
                      opacity: (1.0 - _radarController.value).clamp(0.0, 1.0),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                  // Inner ripple
                  Transform.scale(
                    scale: 1.0 + (((_radarController.value + 0.5) % 1.0) * 0.4),
                    child: Opacity(
                      opacity: (1.0 - ((_radarController.value + 0.5) % 1.0)).clamp(0.0, 1.0),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF43F5E).withValues(alpha: 0.6),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Expert Avatar
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF43F5E), width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.6),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: LocalAvatarWidget(
                      uid: expertUid,
                      role: 'expert',
                      radius: 64, // Prominent large avatar
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // Expert Name
          Text(
            nickname,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
