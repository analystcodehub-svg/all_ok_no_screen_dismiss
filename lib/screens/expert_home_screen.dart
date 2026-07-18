import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../services/call_service.dart';
import '../services/matchmaking_service.dart';
import 'upgrade_program_screen.dart';
import 'withdraw_screen.dart';
import 'incoming_call_screen.dart';
import '../services/notification_service.dart';
import '../services/hybrid_chat_service.dart';
import '../widgets/local_avatar_widget.dart';

class ExpertHomeScreen extends StatefulWidget {
  const ExpertHomeScreen({super.key});

  @override
  State<ExpertHomeScreen> createState() => _ExpertHomeScreenState();
}

class _ExpertHomeScreenState extends State<ExpertHomeScreen>
    with TickerProviderStateMixin {
  bool _isAudioOn = false;
  int _totalTalktimeMinutes = 0;
  double _redeemableBalance = 0.0;
  bool _isLoadingStats = true;

  final CallService _callService = CallService();
  late final MatchmakingService _matchingService;
  StreamSubscription? _incomingCallSubscription;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _cardSlideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _matchingService = MatchmakingService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.08).animate(_pulseController);

    _cardSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _cardSlideController, curve: Curves.easeOutCubic));
    _cardSlideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance.signInAnonymously();
        } catch (_) {}
      }
      _fetchExpertStats();
      if (!mounted) return;
      final appState = context.read<AppState>();
      setState(() => _isAudioOn = appState.isOnline);
      final String expertId = appState.uid;
      if (appState.isOnline) {
        _startIncomingCallListener(expertId);
      }
      
      // Initialize Chat Listeners for Female Expert
      if (expertId.isNotEmpty) {
        HybridChatService().initListeners(expertId);
      }
    });
  }

  @override
  void dispose() {
    HybridChatService().dispose();
    _incomingCallSubscription?.cancel();
    _pulseController.dispose();
    _cardSlideController.dispose();
    super.dispose();
  }

  // ── Firestore ──────────────────────────────────────────────────────────

  Future<void> _fetchExpertStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    final appState = context.read<AppState>();
    final expertId = appState.uid;
    if (expertId.isEmpty) {
      setState(() => _isLoadingStats = false);
      return;
    }
    
    // Save FCM Token for push notifications
    await NotificationService.instance.saveTokenForUser(
      userId: expertId,
      collection: 'experts',
    );
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('experts')
          .doc(expertId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _totalTalktimeMinutes =
              (data['totalTalktimeMinutes'] as num?)?.toInt() ?? 0;
          _redeemableBalance =
              (data['redeemableBalance'] as num?)?.toDouble() ?? 0.0;
        });
        
        if (data.containsKey('avatarIndex')) {
          context.read<AppState>().setAvatarIndex((data['avatarIndex'] as num).toInt());
        }
      }
    } catch (e) {
      debugPrint('Error fetching expert stats: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _updateOnlineStatus(bool value) async {
    final appState = context.read<AppState>();
    appState.setOnlineStatus(value);
    setState(() => _isAudioOn = value);

    final String expertId = appState.uid;
    debugPrint('[STATUS] nickname=${appState.nickname} expertId=$expertId mobileNumber=${appState.mobileNumber} value=$value');
    if (expertId.isNotEmpty) {
      try {
        await _matchingService.setExpertOnlineStatus(
          expertId: expertId,
          isOnline: value,
          gender: 'female',
          language: appState.primaryLanguage,
        );
        debugPrint('[STATUS] RTDB queue updated for $expertId → $value');
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
        }, SetOptions(merge: true));
        debugPrint('[STATUS] Firestore updated experts/$expertId');
      } catch (e) {
        debugPrint('[STATUS] ERROR updating online status: $e');
      }
    } else {
      debugPrint('[STATUS] expertId is EMPTY — skipping Firestore update!');
    }
    if (value) {
      _startIncomingCallListener(expertId);
    } else {
      _incomingCallSubscription?.cancel();
    }
  }

  void _startIncomingCallListener(String expertId) {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _callService.listenForIncomingCalls(
      expertId: expertId,
      onCallReceived: (roomId, callerId) =>
          _showIncomingCallDialog(roomId, callerId),
    );
  }

  void _showIncomingCallDialog(String roomId, String callerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncomingCallScreen(
          callRoomId: roomId,
          callerId: callerId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _fetchExpertStats();
      }
    });
  }

  /// Check KYC status in Firestore, then route accordingly
  Future<void> _showWithdrawDialog() async {
    if (_redeemableBalance < 99) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Minimum withdrawal amount is ₹99.'),
          backgroundColor: AppColors.textGrey));
      return;
    }

    final nickname = context.read<AppState>().uid;

    // Query KYC status from Firestore
    bool kycApproved = false;
    try {
      // Check by expertId (new submissions)
      var snap = await FirebaseFirestore.instance
          .collection('kyc_requests')
          .where('expertId', isEqualTo: nickname)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        // Fallback: check all docs for matching accountHolder
        final all = await FirebaseFirestore.instance
            .collection('kyc_requests')
            .limit(10)
            .get();
        for (final doc in all.docs) {
          final d = doc.data();
          final holder = (d['accountHolder'] ?? '').toString().toLowerCase();
          final eid = (d['expertId'] ?? '').toString();
          if (holder == nickname || eid == nickname) {
            snap = await FirebaseFirestore.instance
                .collection('kyc_requests')
                .where(FieldPath.documentId, isEqualTo: doc.id)
                .get();
            break;
          }
        }
      }

      if (snap.docs.isNotEmpty) {
        final status = snap.docs.first.data()['status'] ?? 'pending';
        kycApproved = status == 'approved';
      }
    } catch (_) {}

    if (!mounted) return;

    if (kycApproved) {
      // ✅ KYC done — show the standard popup
      _showKycApprovedWithdrawDialog();
    } else {
      // ❌ KYC not done — open WithdrawScreen with TDS warning
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WithdrawScreen(amount: _redeemableBalance),
        ),
      );
      if (result == true && mounted) {
        setState(() => _redeemableBalance = 0.0);
      }
    }
  }

  /// Standard withdraw popup shown only when KYC is approved
  void _showKycApprovedWithdrawDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Withdraw Earnings',
            style: TextStyle(
                color: AppColors.textDark, fontWeight: FontWeight.bold)),
        content: Text(
          'Withdraw ₹${_redeemableBalance.toStringAsFixed(0)} to your registered bank account?\n\nTransfer takes 3–5 business days.',
          style: const TextStyle(color: AppColors.textGrey),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _processWithdrawal();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _processWithdrawal() async {
    final expertId = context.read<AppState>().uid;
    if (expertId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('withdrawal_requests').add({
        'expertId': expertId,
        'amount': _redeemableBalance,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('experts')
          .doc(expertId)
          .update({'redeemableBalance': 0.0});
      if (mounted) {
        setState(() => _redeemableBalance = 0.0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Withdrawal request submitted!'),
            backgroundColor: AppColors.successGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // Use nickname from AppState — the actual registered name, not "Expert"
    final String displayName = appState.nickname.isNotEmpty
        ? appState.nickname
        : 'there';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: _fetchExpertStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(displayName, appState),
                  _buildAvailabilityCard(),
                  _buildStatsCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 1. Header ──────────────────────────────────────────────────────────
  Widget _buildHeader(String displayName, AppState appState) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + logout
          Row(
            children: [
              // Pulsing avatar
              ScaleTransition(
                scale: _isAudioOn ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isAudioOn ? AppColors.successGreen : Colors.white38,
                      width: 3,
                    ),
                  ),
                  child: LocalAvatarWidget(
                    uid: appState.uid,
                    role: 'expert',
                    radius: 28,
                    avatarIndex: appState.avatarIndex,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Greeting
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi, $displayName 👋',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isAudioOn
                                ? AppColors.successGreen
                                : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isAudioOn
                              ? 'Online · Ready for calls'
                              : 'Offline · Not receiving calls',
                          style: TextStyle(
                            fontSize: 13,
                            color: _isAudioOn
                                ? Colors.greenAccent.shade100
                                : Colors.white60,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Balance pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white30, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '₹${_redeemableBalance.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

            ],
          ),

        ],
      ),
    );
  }

  // ── 2. Availability Card ───────────────────────────────────────────────
  Widget _buildAvailabilityCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.lightBlueBg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppColors.primaryBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.wifi_tethering,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Availability Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          // Audio toggle
          Padding(
            padding: const EdgeInsets.all(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _isAudioOn
                    ? AppColors.successGreen.withValues(alpha: 0.08)
                    : AppColors.bgLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isAudioOn
                      ? AppColors.successGreen.withValues(alpha: 0.4)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  // Icon with animated bg
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isAudioOn
                          ? AppColors.successGreen.withValues(alpha: 0.15)
                          : AppColors.lightBlueBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isAudioOn ? Icons.phone_in_talk : Icons.phone_disabled,
                      color: _isAudioOn
                          ? AppColors.successGreen
                          : AppColors.primaryBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Label
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Audio Calls',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark)),
                        const SizedBox(height: 2),
                        Text(
                          _isAudioOn
                              ? 'You are receiving calls'
                              : 'Turn on to receive calls',
                          style: TextStyle(
                              fontSize: 12,
                              color: _isAudioOn
                                  ? AppColors.successGreen
                                  : AppColors.textGrey),
                        ),
                      ],
                    ),
                  ),
                  // Switch
                  Switch(
                    value: _isAudioOn,
                    activeTrackColor: AppColors.successGreen,
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor:
                        AppColors.textGrey.withValues(alpha: 0.3),
                    onChanged: (val) => _updateOnlineStatus(val),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Stats Card ──────────────────────────────────────────────────────
  Widget _buildStatsCard() {
    final String expertId = context.read<AppState>().uid;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.lightBlueBg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppColors.primaryBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.bar_chart_rounded,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Total Activity",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _fetchExpertStats,
                  child: const Icon(Icons.refresh_rounded,
                      color: AppColors.primaryBlue, size: 20),
                ),
              ],
            ),
          ),

          if (_isLoadingStats)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Stats Row
                  Row(
                    children: [
                      // Talktime stat
                      Expanded(
                        child: _buildStatTile(
                          icon: Icons.timer_outlined,
                          iconColor: AppColors.primaryBlue,
                          value: '$_totalTalktimeMinutes m',
                          label: 'Total Talktime',
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Balance stat
                      Expanded(
                        child: _buildStatTile(
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: AppColors.successGreen,
                          value:
                              '₹${_redeemableBalance.toStringAsFixed(0)}',
                          label: 'Redeemable Balance',
                          valueColor: AppColors.successGreen,
                          trailing: Tooltip(
                            message:
                                'Amount available after platform fee deduction.',
                            child: const Icon(Icons.info_outline,
                                size: 14, color: AppColors.textGrey),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Withdraw button
                  GestureDetector(
                    onTap: _showWithdrawDialog,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: AppColors.primaryBlue, width: 1.5),
                        gradient: _redeemableBalance > 0
                            ? const LinearGradient(
                                colors: [
                                  AppColors.primaryBlue,
                                  Color(0xFF1565C0)
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : null,
                        color: _redeemableBalance > 0
                            ? null
                            : Colors.transparent,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_rounded,
                            size: 18,
                            color: _redeemableBalance > 0
                                ? Colors.white
                                : AppColors.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Withdraw',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _redeemableBalance > 0
                                  ? Colors.white
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Upgrade Program button
                  GestureDetector(
                    onTap: _showUpgradeDialog,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFFA000), // Amber 700
                            Color(0xFFFFD54F), // Amber 300
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 18,
                            color: Color(0xFF5D4037),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Upgrade Program',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5D4037),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (expertId.isNotEmpty)
                    _buildWithdrawalRequestsList(expertId),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    Color valueColor = AppColors.textDark,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.lightBlueBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing,
              ]
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildWithdrawalRequestsList(String expertId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawal_requests')
          .where('expertId', isEqualTo: expertId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.hasData ? snapshot.data!.docs : [];
        
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Sort in memory by requestedAt descending
        final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
        sortedDocs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        return Column(
          children: sortedDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _buildWithdrawalRequestCard(data, doc.id);
          }).toList(),
        );
      },
    );
  }

  Widget _buildWithdrawalRequestCard(Map<String, dynamic> data, String docId) {
    final status = data['status'] ?? 'pending';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final timestamp = data['requestedAt'] as Timestamp?;

    // Format timestamp
    String formattedTime = '';
    if (timestamp != null) {
      final dateTime = timestamp.toDate();
      final hourNum = dateTime.hour > 12
          ? dateTime.hour - 12
          : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final amPm = dateTime.hour >= 12 ? 'pm' : 'am';
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year.toString().substring(2);
      formattedTime = '$hourNum:$minute $amPm • $day/$month/$year';
    } else {
      formattedTime = 'Just now';
    }

    // Short txn ID for display (e.g. first 8 characters)
    final txnIdDisplay = docId.length > 8 ? docId.substring(0, 8).toUpperCase() : docId.toUpperCase();

    Color statusColor = const Color(0xFFF59E0B); // Pending orange
    String statusText = 'Pending';
    if (status == 'approved' || status == 'success') {
      statusColor = Colors.green;
      statusText = 'Successful';
    } else if (status == 'failed' || status == 'rejected') {
      statusColor = Colors.red;
      statusText = 'Failed';
    } else {
      statusText = status.substring(0, 1).toUpperCase() + status.substring(1);
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status bar/line
              Container(
                width: 4,
                color: statusColor,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Info Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SajniRe Cashout (₹${amount.toStringAsFixed(0)})',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$formattedTime • Txn ID: $txnIdDisplay',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: docId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Transaction ID copied!'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: const Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Gray bottom bar
                    Container(
                      color: const Color(0xFFF8FAFC), // Very light grey
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.headset_mic_outlined,
                            size: 15,
                            color: AppColors.primaryBlue.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Help',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpgradeDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UpgradeProgramScreen(),
      ),
    );
  }
}
