import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'local_avatar_widget.dart';

class ExpertCard extends StatelessWidget {
  final String expertId;
  final String nickname;
  final String language;
  final VoidCallback onCallTap;
  final VoidCallback onChatTap;
  final bool isOnline;

  const ExpertCard({
    Key? key,
    required this.expertId,
    required this.nickname,
    required this.language,
    required this.onCallTap,
    required this.onChatTap,
    this.isOnline = true,
  }) : super(key: key);

  int get displayAge {
    if (expertId.isEmpty) return 22;
    return (expertId.hashCode.abs() % 6) + 20; 
  }

  String get displayRating {
    if (expertId.isEmpty) return "4.5";
    int hash = expertId.hashCode.abs();
    double rating = (40 + (hash % 11)) / 10;
    return rating.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  LocalAvatarWidget(
                    uid: expertId,
                    role: 'expert',
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nickname,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StreamBuilder<DatabaseEvent>(
                                  stream: FirebaseDatabase.instanceFor(
                                    app: FirebaseDatabase.instance.app,
                                    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
                                  ).ref('status/$expertId/isOnline').onValue,
                                  builder: (context, snapshot) {
                                    bool currentOnline = isOnline; // default to initial
                                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                                      currentOnline = snapshot.data!.snapshot.value == true;
                                    }
                                    return Icon(
                                      Icons.fiber_manual_record,
                                      size: 10,
                                      color: currentOnline ? Colors.green : Colors.grey,
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$displayAge Yrs',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  displayRating,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.language_rounded, size: 12, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            Text(
                              language,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.w500,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onChatTap,
                  icon: const Icon(Icons.chat_bubble_rounded),
                  color: Colors.blue,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: onCallTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text(
                    'Call',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
