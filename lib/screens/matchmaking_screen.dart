import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/female_expert.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../services/matchmaking_service.dart';
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
      backgroundColor: const Color(0xFF0F172A), // Dark slate background
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            
            // Radar Animation
            Center(
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
                  
                  // Center Avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E293B), // Slate 800
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ],
              ),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      '00:${timerValue.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Color(0xFFF43F5E),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
