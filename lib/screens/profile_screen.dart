import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import 'kyc_pan_screen.dart';
import 'referral_screen.dart';
import 'withdrawal_history_screen.dart';
import '../widgets/local_avatar_widget.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          final nickname = appState.nickname.isNotEmpty ? appState.nickname : 'User';
          final uid = appState.selectedGender == 'Female' ? appState.uid : appState.mobileNumber;
          final role = appState.selectedGender == 'Female' ? 'expert' : 'user';
              
          return SingleChildScrollView(
            child: Column(
              children: [
                // Header with Blue Background and overlapping Grid
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Top Blue Background
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryBlue,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          // Avatar with Edit Button
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [AppColors.gradientLightBlueStart, AppColors.gradientBlueEnd],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.white,
                                  child: LocalAvatarWidget(
                                    uid: uid,
                                    role: role,
                                    radius: 46,
                                  ),
                                ),
                              ),
                              // Edit FAB
                              Positioned(
                                bottom: 0,
                                right: -5,
                                child: InkWell(
                                  onTap: () {
                                    // Note: Implement Edit Profile
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryBlue,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Username
                          Text(
                            nickname,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Spacing to push content below the header
                const SizedBox(height: 24),

                // KYC & Profile Sections
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKycStatusSection(context, uid, appState.nickname),
                      const SizedBox(height: 12),
                      _buildReferralTile(context),
                      const SizedBox(height: 24),
                      
                      // Transaction Ledger Section
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Transaction Ledger',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsTile(
                        title: 'Withdrawal History',
                        icon: Icons.history_rounded,
                        iconColor: AppColors.primaryBlue,
                        iconBgColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const WithdrawalHistoryScreen()),
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Settings & Support Section
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Settings & Support',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsTile(
                        title: 'Terms & Condition',
                        icon: Icons.description,
                        iconColor: Colors.orange,
                        iconBgColor: Colors.orange.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsTile(
                        title: 'Refund & Cancellation',
                        icon: Icons.attach_money,
                        iconColor: AppColors.successGreen,
                        iconBgColor: AppColors.successGreen.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap ?? () {},
      ),
    );
  }

  Widget _buildReferralTile(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReferralScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.card_giftcard_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refer & Earn',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Invite friends and grow your network',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildKycStatusSection(BuildContext context, String uid, String nickname) {
    // Query by expertId (new submissions) — no orderBy to avoid index requirement
    final stream = FirebaseFirestore.instance
        .collection('kyc_requests')
        .where('expertId', isEqualTo: uid)
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Fallback: query by accountHolder name for old documents
          return _buildKycByAccountHolder(context, nickname, uid);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildKycButton(context);
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          // No doc with expertId — try accountHolder for pre-fix submissions
          return _buildKycByAccountHolder(context, nickname, uid);
        }

        final data = docs.first.data() as Map<String, dynamic>;
        return _kycCardForStatus(context, data['status'] ?? 'pending');
      },
    );
  }

  // Fallback query for documents submitted before expertId was added
  Widget _buildKycByAccountHolder(BuildContext context, String nickname, String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('kyc_requests')
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildKycButton(context);
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildKycButton(context);

        // Find any doc where accountHolder or panName matches
        QueryDocumentSnapshot? match;
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final holder = (d['accountHolder'] ?? '').toString().toLowerCase();
          final pan = (d['panName'] ?? '').toString().toLowerCase();
          final eid = (d['expertId'] ?? '').toString();
          if (holder == nickname.toLowerCase() ||
              pan == nickname.toLowerCase() ||
              eid == uid) {
            match = doc;
            break;
          }
        }

        if (match == null) return _buildKycButton(context);

        final data = match.data() as Map<String, dynamic>;
        return _kycCardForStatus(context, data['status'] ?? 'pending');
      },
    );
  }

  Widget _kycCardForStatus(BuildContext context, String status) {
    if (status == 'approved') return _buildKycApprovedCard();
    if (status == 'rejected') return _buildKycRejectedCard(context);
    return _buildKycPendingCard();
  }

  Widget _buildKycApprovedCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.verified_user_rounded,
                color: Colors.green.shade600, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KYC Successful ✅',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'You can now withdraw your earnings.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKycPendingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KYC Under Review ⏳',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'We\'ll verify your details within 24–48 hours.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKycRejectedCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const KycPanScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Icon(Icons.cancel_rounded, color: Colors.red.shade600, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KYC Rejected ❌',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap to re-submit your KYC details.',
                    style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildKycButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KycPanScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.lightBlueBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: AppColors.primaryBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KYC Verification',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Complete to enable withdrawals',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Start KYC',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
