import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';

class WithdrawalHistoryScreen extends StatelessWidget {
  const WithdrawalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final expertId = context.read<AppState>().uid;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Withdrawal History'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 1,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('withdrawal_requests')
              .where('expertId', isEqualTo: expertId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue));
            }

            final docs = snapshot.hasData ? snapshot.data!.docs : [];
            
            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  'No withdrawal requests found.',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 16),
                ),
              );
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

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedDocs.length,
              itemBuilder: (context, index) {
                final doc = sortedDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                return _buildWithdrawalRequestCard(data, doc.id, context);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildWithdrawalRequestCard(Map<String, dynamic> data, String docId, BuildContext context) {
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: docId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Transaction ID copied!')),
                                  );
                                },
                                child: const Icon(Icons.copy, size: 14, color: AppColors.textGrey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Divider
                    Container(height: 1, color: Colors.grey.shade100),
                    // Bottom Action Row
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.support_agent_rounded, size: 16, color: AppColors.primaryBlue.withOpacity(0.8)),
                          const SizedBox(width: 6),
                          Text(
                            'Help',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue.withOpacity(0.8),
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
}
