import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _codeCopied = false;

  String _generateCode(String nickname) {
    final clean = nickname.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final suffix = (clean.hashCode.abs() % 9000 + 1000).toString();
    return '${clean.substring(0, clean.length.clamp(0, 5))}$suffix';
  }

  @override
  void initState() {
    super.initState();
    // Persist referral code to Firestore so new users can validate it at signup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final nickname = context.read<AppState>().nickname;
      final code = _generateCode(nickname);
      try {
        final existing = await FirebaseFirestore.instance
            .collection('experts')
            .where('referralCode', isEqualTo: code)
            .limit(1)
            .get();
        if (existing.docs.isEmpty) {
          // Save if not already present
          await FirebaseFirestore.instance.collection('experts').add({
            'nickname': nickname,
            'referralCode': code,
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _codeCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied!'),
        backgroundColor: AppColors.successGreen,
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _codeCopied = false);
    });
  }

  Future<void> _shareCode(String code, String nickname) async {
    final message =
        'Join SajniRe and start earning! Use my referral code: $code\n'
        'Download the app and enter this code during sign-up to get started. 🎉';
    await Clipboard.setData(ClipboardData(text: message));
    // Use Android share sheet via platform channel
    const platform = MethodChannel('flutter/platform');
    try {
      await platform.invokeMethod('Share.share', {'text': message});
    } catch (_) {
      // Fallback: just show copy confirmation
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message copied! Paste it to share with friends.'),
          backgroundColor: AppColors.primaryBlue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nickname = context.read<AppState>().nickname;
    final referralCode = _generateCode(nickname);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text(
          'Refer & Earn',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue,
                    AppColors.gradientBlueEnd,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.card_giftcard_rounded,
                      color: Colors.white, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Invite Friends & Earn',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Share your code. When a friend joins using\nyour code, both of you benefit!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Referral Code Box
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'YOUR REFERRAL CODE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              referralCode,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _copyCode(referralCode),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _codeCopied
                                      ? Colors.green.shade50
                                      : AppColors.lightBlueBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _codeCopied
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  color: _codeCopied
                                      ? Colors.green
                                      : AppColors.primaryBlue,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Share Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _shareCode(referralCode, nickname),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share Referral Code',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Stats Row
            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildReferralStats(referralCode),
            ),

            // Members List
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 4, height: 20, color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      const Text(
                        'Referred Members',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildReferredMembersList(referralCode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralStats(String referralCode) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('referrals')
          .where('referralCode', isEqualTo: referralCode)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Row(
          children: [
            Expanded(
              child: _buildStatBox(
                icon: Icons.people_alt_rounded,
                color: AppColors.primaryBlue,
                value: '$count',
                label: 'Total Referred',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatBox(
                icon: Icons.emoji_events_rounded,
                color: Colors.amber.shade700,
                value: count > 0 ? 'Active' : 'None yet',
                label: 'Referral Status',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatBox({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReferredMembersList(String referralCode) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('referrals')
          .where('referralCode', isEqualTo: referralCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.group_add_rounded,
                    size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text(
                  'No referrals yet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Share your code and your referred\nmembers will appear here.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textGrey),
                ),
              ],
            ),
          );
        }

        // Sort in memory by joinedAt descending
        final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
        sortedDocs.sort((a, b) {
          final aT =
              (a.data() as Map<String, dynamic>)['joinedAt'] as Timestamp?;
          final bT =
              (b.data() as Map<String, dynamic>)['joinedAt'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });

        return Column(
          children: sortedDocs.asMap().entries.map((entry) {
            final idx = entry.key;
            final doc = entry.value;
            final data = doc.data() as Map<String, dynamic>;
            final name = data['referredName'] ?? 'User';
            final phone = data['referredPhone'] ?? '';
            final joinedAt = data['joinedAt'] as Timestamp?;
            final status = data['status'] ?? 'joined';

            String formattedDate = 'Just now';
            if (joinedAt != null) {
              final d = joinedAt.toDate();
              formattedDate =
                  '${d.day}/${d.month}/${d.year.toString().substring(2)}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Avatar circle with index
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gradientBlueStart,
                          AppColors.gradientBlueEnd
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phone.isNotEmpty ? phone : 'Joined $formattedDate',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'active'
                          ? Colors.green.shade50
                          : AppColors.lightBlueBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status == 'active' ? 'Active' : 'Joined',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: status == 'active'
                            ? Colors.green.shade700
                            : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
