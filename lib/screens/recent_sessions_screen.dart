import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import '../services/local_chat_database.dart';
import '../widgets/local_avatar_widget.dart';
class RecentSessionsScreen extends StatefulWidget {
  const RecentSessionsScreen({super.key});

  @override
  State<RecentSessionsScreen> createState() => _RecentSessionsScreenState();
}

class _RecentSessionsScreenState extends State<RecentSessionsScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final String currentUserId = appState.uid;
    
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.only(left: 20, top: 20, bottom: 10),
              child: Text(
                'Recent Session',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),

            // List View connected to local 'call_logs' table
            Expanded(
              child: StreamBuilder<void>(
                stream: LocalChatDatabase.instance.updates,
                builder: (context, snapshot) {
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: LocalChatDatabase.instance.getRecentCallLogs(currentUserId),
                    builder: (context, futureSnapshot) {
                      if (futureSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (futureSnapshot.hasError) {
                        return Center(child: Text('Error loading calls: ${futureSnapshot.error}'));
                      }

                      final allCalls = futureSnapshot.data ?? [];
                      if (allCalls.isEmpty) {
                        return _buildEmptyState();
                      }

                      if (allCalls.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: allCalls.length,
                        itemBuilder: (context, index) {
                          final data = allCalls[index];
                          
                          final isCaller = data['callerId'] == currentUserId;
                          final String? otherUserId = (isCaller ? data['receiverId'] : data['callerId'])?.toString();
                          final isMissed = data['status'] == 'missed';
                          
                          String timeText = 'Just now';
                          String initialName = (data['otherUserName']?.toString() ?? '').trim();
                          if (initialName.isEmpty) initialName = 'Loading...';
                          
                          if (data['timestamp'] != null) {
                            final dt = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
                            final now = DateTime.now();
                            if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                              timeText = TimeOfDay.fromDateTime(dt).format(context);
                            } else {
                              timeText = '${dt.day}/${dt.month}';
                            }
                          }

                          // Determine duration text and cost
                          String durationText = isMissed ? 'Missed Call' : 'Ended';
                          String costText = isMissed ? '₹0' : 'Ended';
                          
                          if (!isMissed && data['durationSeconds'] != null) {
                            final sec = data['durationSeconds'] as int;
                            final m = sec ~/ 60;
                            final s = sec % 60;
                            durationText = '${m}m ${s}s';
                            
                            int callMinutes = sec ~/ 60;
                            if (sec % 60 >= 50) {
                              callMinutes += 1;
                            }
                            
                            if (isCaller) {
                              // Caller is User (Male), uses Coins
                              costText = '-${callMinutes * 50} Coins';
                            } else {
                              // Receiver is Expert (Female), earns Rupees
                              costText = '+₹${callMinutes.toStringAsFixed(1)}';
                            }
                          }

                          final collectionName = isCaller ? 'experts' : 'users';
                          
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection(collectionName).doc(otherUserId).get(),
                            builder: (context, profileSnapshot) {
                              String displayName = initialName;
                              
                              if (profileSnapshot.connectionState == ConnectionState.done) {
                                if (profileSnapshot.hasData && profileSnapshot.data!.exists) {
                                  final profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
                                  if (profileData['nickname'] != null && profileData['nickname'].toString().trim().isNotEmpty) {
                                    displayName = profileData['nickname'];
                                  } else {
                                    displayName = isCaller ? 'Expert' : 'User';
                                  }
                                } else {
                                  displayName = isCaller ? 'Expert' : 'User';
                                }
                              }

                              return _buildCallCard(
                                name: displayName,
                                timeText: timeText,
                                duration: durationText,
                                cost: costText,
                                isMissed: isMissed,
                                otherUserId: otherUserId ?? '',
                                isCaller: isCaller,
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  

  
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 64, color: AppColors.textGrey),
          SizedBox(height: 16),
          Text(
            'No recent sessions yet.',
            style: TextStyle(fontSize: 18, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildCallCard({
    required String name,
    required String timeText,
    required String duration,
    required String cost,
    required bool isMissed,
    required String otherUserId,
    required bool isCaller,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with gradient border
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isMissed 
                  ? [Colors.red.shade300, Colors.red.shade700] 
                  : [AppColors.gradientBlueStart, AppColors.gradientBlueEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white,
              child: LocalAvatarWidget(
                uid: otherUserId,
                role: isCaller ? 'expert' : 'user',
                radius: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isMissed ? Colors.red.shade700 : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      isMissed ? Icons.phone_missed : Icons.access_time, 
                      size: 14, 
                      color: isMissed ? Colors.red : AppColors.primaryBlue
                    ),
                    const SizedBox(width: 4),
                    Text(
                      duration,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isMissed ? Colors.red : AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              /*
              GestureDetector(
                onTap: () => _triggerCall(context, otherUserId, !isCaller),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.phone, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              */
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isMissed 
                    ? Colors.red.withValues(alpha: 0.1) 
                    : AppColors.successGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  cost,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isMissed ? Colors.red : AppColors.successGreen,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
