import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import '../widgets/local_avatar_widget.dart';
import 'active_call_page.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callRoomId;
  final String callerId;

  const IncomingCallScreen({
    super.key,
    required this.callRoomId,
    required this.callerId,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final CallService _callService = CallService();
  StreamSubscription<DatabaseEvent>? _callSub;
  bool _isDismissing = false;
  late Future<String> _callerNameFuture;
  String _callerName = "User";

  Future<String> _fetchCallerName() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.callerId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['nickname'] != null && data['nickname'].toString().isNotEmpty) {
          final name = data['nickname'].toString();
          if (mounted) {
            setState(() {
              _callerName = name;
            });
          }
          return name;
        }
      }
    } catch (e) {
      debugPrint("Error fetching caller name: $e");
    }
    return "User";
  }

  @override
  void initState() {
    super.initState();
    _callerNameFuture = _fetchCallerName();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      // For experts, their Firestore document ID is ALWAYS appState.uid.
      final String currentUserId = appState.uid;
      
      if (currentUserId.isNotEmpty) {
        // Crucial for MatchmakingService: set 'status' to 'ringing' in active_calls lock
        FirebaseDatabase.instanceFor(
          app: FirebaseDatabase.instance.app,
          databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
        ).ref('active_calls/$currentUserId').update({
          'status': 'ringing',
        }).catchError((e) => debugPrint('Error setting active_calls status: $e'));

        // Keep the existing profile status update as well
        FirebaseDatabase.instanceFor(
          app: FirebaseDatabase.instance.app,
          databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
        ).ref('status/$currentUserId').update({
          'callStatus': 'ringing',
        }).catchError((e) => debugPrint('Error setting ringing status: $e'));
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _callSub = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
    )
        .ref('calls/${widget.callRoomId}')
        .onValue
        .listen((event) {
      if (event.snapshot.value == null) {
        _handleCallEndedRemotely();
        return;
      }
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      if (data['status'] == 'ended') {
        _handleCallEndedRemotely();
      }
    });
  }

  void _handleCallEndedRemotely() {
    if (_isDismissing) return;
    _isDismissing = true;
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missed Call: Caller disconnected')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _acceptCall() {
    if (_isDismissing) return;
    _isDismissing = true;
    
    final appState = context.read<AppState>();
    // For experts, their Firestore document ID is ALWAYS appState.uid.
    final currentUserId = appState.uid;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveCallPage(
          callRoomId: widget.callRoomId,
          receiverId: currentUserId,
          callerId: widget.callerId,
          nickname: _callerName,
          pricePerMin: 5.0,
          isCaller: false,
        ),
      ),
    );
  }

  void _declineCall() {
    if (_isDismissing) return;
    _isDismissing = true;
    
    _callService.endCall(widget.callRoomId);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate premium bg
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            
            // Header text
            const Text(
              'Incoming Call',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: _callerNameFuture,
              builder: (context, snapshot) {
                final displayName = snapshot.data ?? 'User';
                return Text(
                  displayName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
            
            const Spacer(flex: 3),
            
            // Pulsing Avatar
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rings
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: List.generate(3, (index) {
                          final delay = index * 0.33;
                          double progress =
                              (_pulseController.value + delay) % 1.0;
                          return Transform.scale(
                            scale: 1.0 + (progress * 1.5),
                            child: Opacity(
                              opacity: (1.0 - progress).clamp(0.0, 1.0),
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.greenAccent,
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
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E293B),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.3),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: LocalAvatarWidget(
                      uid: widget.callerId,
                      role: 'user', // Assuming callers are always users
                      radius: 70,
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(flex: 4),
            
            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Decline
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _declineCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Decline',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  
                  // Accept
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _acceptCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.shade700,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.greenAccent.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Accept',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
