import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/app_state.dart';
import '../services/call_service.dart';
import 'active_call_page.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callRoomId;
  final String callerId;
  final VoidCallback? onCallEnded;

  const IncomingCallScreen({
    super.key,
    required this.callRoomId,
    required this.callerId,
    this.onCallEnded,
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
  late Future<Map<String, dynamic>> _callerDataFuture;
  Timer? _vibrateTimer;

  Future<Map<String, dynamic>> _fetchCallerData() async {
    Map<String, dynamic> result = {
      'nickname': 'User',
      'avatarUrl': null,
      'avatarIndex': 1,
      'coinBalance': 0,
      'hasUsedFreeCall': true,
    };
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.callerId)
          .get()
          .timeout(const Duration(seconds: 2));
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['nickname'] != null && data['nickname'].toString().isNotEmpty) {
          result['nickname'] = data['nickname'].toString();
        }
        result['avatarUrl'] = data['profileImageUrl'] ?? data['avatarUrl'];
        result['avatarIndex'] = (data['avatarIndex'] as num?)?.toInt() ?? 1;
        result['coinBalance'] = (data['coinBalance'] as num?)?.toInt() ?? 0;
        result['hasUsedFreeCall'] = data['hasUsedFreeCall'] as bool? ?? false;
      }
    } catch (e) {
      debugPrint("Error fetching caller data: $e");
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _callerDataFuture = _fetchCallerData();
    
    // Start playing system ringtone and vibration when the screen opens
    FlutterRingtonePlayer().play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.glass,
      looping: true,
      volume: 1.0,
      asAlarm: true, // Forces it to play out loud
    );
    
    // Continuous real vibration using vibration package
    _vibrateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      Vibration.vibrate(duration: 1000); // Vibrate for 1 second every 2 seconds
    });
    
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
    _vibrateTimer?.cancel();
    FlutterRingtonePlayer().stop();
    _callSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _acceptCall() async {
    if (_isDismissing) return;
    _isDismissing = true;
    
    final appState = context.read<AppState>();
    // For experts, their Firestore document ID is ALWAYS appState.uid.
    final currentUserId = appState.uid;
    
    final callerData = await _callerDataFuture;
    
    _vibrateTimer?.cancel();
    FlutterRingtonePlayer().stop();
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(
            callRoomId: widget.callRoomId,
            receiverId: currentUserId,
            callerId: widget.callerId,
            nickname: callerData['nickname'] ?? 'User',
            avatarUrl: callerData['avatarUrl'] as String?,
            avatarIndex: (callerData['avatarIndex'] as num?)?.toInt() ?? 1,
            pricePerMin: 3.0,
            isCaller: false,
            callerCoinBalance: (callerData['coinBalance'] as num?)?.toInt() ?? 0,
            callerHasUsedFreeCall: callerData['hasUsedFreeCall'] as bool? ?? true,
            onCallEnded: widget.onCallEnded,
          ),
        ),
      );
    }
  }

  void _declineCall() {
    if (_isDismissing) return;
    _isDismissing = true;
    
    _vibrateTimer?.cancel();
    FlutterRingtonePlayer().stop();
    
    if (mounted) {
      Navigator.pop(context);
    }
    
    // Perform network call asynchronously after popping
    _callService.endCall(widget.callRoomId).catchError((e) {
      debugPrint('Error ending call: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 80),

                // Caller name
                FutureBuilder<Map<String, dynamic>>(
                  future: _callerDataFuture,
                  builder: (context, snapshot) {
                    final name = (snapshot.data?['nickname'] as String?) ?? 'User';
                    return Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 8),

                const Text(
                  'calling ....',
                  style: TextStyle(
                    color: Color(0xFFA3A3A3),
                    fontSize: 18,
                  ),
                ),

                const Spacer(),

                // ─── Action Buttons ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(
                      left: 40, right: 40, bottom: 60, top: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Decline (Left)
                      _buildActionButton(
                        label: 'Decline',
                        icon: Icons.call_end,
                        color: const Color(0xFFEF4444),
                        onTap: _declineCall,
                      ),

                      // Accept (Right)
                      _buildActionButton(
                        label: 'Accept',
                        icon: Icons.call,
                        color: const Color(0xFF10B981),
                        onTap: _acceptCall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helper Widgets ──────────────────────────────────────────────────────

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
