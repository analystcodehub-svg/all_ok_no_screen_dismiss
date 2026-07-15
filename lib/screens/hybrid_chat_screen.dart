import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_chat_database.dart';
import '../services/hybrid_chat_service.dart';
import '../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/local_avatar_widget.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'wallet_recharge_screen.dart';
class HybridChatScreen extends StatefulWidget {
  final String myUid;
  final String otherUid;
  final String otherUserName;

  const HybridChatScreen({
    super.key,
    required this.myUid,
    required this.otherUid,
    required this.otherUserName,
  });

  @override
  State<HybridChatScreen> createState() => _HybridChatScreenState();
}

class _HybridChatScreenState extends State<HybridChatScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final HybridChatService _chatService = HybridChatService();
  
  late String _roomId;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _dbUpdateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomId = LocalChatDatabase.generateRoomId(widget.myUid, widget.otherUid);
    
    // Set active room to prevent false delivery ACKs when we are actually reading
    HybridChatService.activeChatRoomId = _roomId;

    // Listen to local DB updates (so ticks update instantly)
    _dbUpdateSubscription = LocalChatDatabase.instance.updates.listen((_) {
      if (mounted) _loadMessages();
    });

    _initChat();
  }

  Future<void> _initChat() async {
    await _loadMessages();

    // Fetch unread messages from the OTHER user and mark them as read
    final unreadMsgs = await LocalChatDatabase.instance.getUnreadMessages(_roomId, widget.otherUid);
    for (var msg in unreadMsgs) {
      await _chatService.markAsRead(msg['msgId'] as String, widget.otherUid, widget.myUid);
    }
    
    if (unreadMsgs.isNotEmpty) {
      await _loadMessages(); // Refresh UI after marking read
    }
  }

  Future<void> _loadMessages() async {
    final messages = await LocalChatDatabase.instance.fetchChatHistory(_roomId);
    if (mounted) {
      setState(() {
        _messages = messages;
      });
      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    HybridChatService.activeChatRoomId = null;
    WidgetsBinding.instance.removeObserver(this);
    AppState.syncPendingChatDeductions();
    _dbUpdateSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      AppState.syncPendingChatDeductions();
    }
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;


    final appState = context.read<AppState>();
    
    // If the sender is a Male User, deduct coins or use free messages
    if (appState.selectedGender == 'Male') {
      if (appState.freeMessagesUsed < 5) {
        // Use a free message
        appState.addPendingChatDeduction(coins: 0, freeMsgs: 1);
      } else {
        // Deduct 5 coins (50 paise)
        if (appState.coinBalance < 5) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: Colors.red, size: 28),
                  SizedBox(width: 10),
                  Text('Low Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              content: const Text(
                'You need 50 paise to send a message. Please recharge your wallet to continue chatting.',
                style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletRechargeScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Recharge Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          return;
        }
        
        // Deduct locally and save to SharedPreferences
        appState.addPendingChatDeduction(coins: 5, freeMsgs: 0);
      }
      
      // Batch sync rule: Sync after 5 messages
      if (appState.pendingChatFreeMsgs >= 5 || appState.pendingChatCoins >= 25) {
        AppState.syncPendingChatDeductions();
        appState.clearPendingChatDeductionsLocally();
      }
    }

    _textController.clear();
    
    await _chatService.sendMessage(
      roomId: _roomId,
      senderUid: widget.myUid,
      receiverUid: widget.otherUid,
      text: text,
    );
  }

  Widget _buildTickIcon(int status) {
    if (status == 1) {
      return const Icon(Icons.check, size: 16, color: Colors.grey);
    } else if (status == 2) {
      return const Icon(Icons.done_all, size: 16, color: Colors.grey);
    } else if (status >= 3) {
      return const Icon(Icons.done_all, size: 16, color: AppColors.primaryBlue);
    }
    return const SizedBox(width: 16);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final otherRole = appState.selectedGender == 'Female' ? 'user' : 'expert';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // WhatsApp-like background
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientBlueStart, AppColors.gradientBlueEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                LocalAvatarWidget(
                  uid: widget.otherUid,
                  role: otherRole,
                  radius: 20,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: StreamBuilder<DatabaseEvent>(
                    stream: FirebaseDatabase.instanceFor(
                      app: FirebaseDatabase.instance.app,
                      databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
                    ).ref('status/${widget.otherUid}/isOnline').onValue,
                    builder: (context, snapshot) {
                      Color statusColor = Colors.grey;
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        final isOnline = snapshot.data!.snapshot.value == true;
                        statusColor = isOnline ? Colors.green : Colors.grey;
                      }
                      return Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryBlue, width: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.otherUserName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['senderId'] == widget.myUid;
                final text = msg['text'] as String;
                final timestamp = msg['timestamp'] as int;
                final status = msg['status'] as int;
                
                final timeStr = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(timestamp)).format(context);

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.lightBlueBg : Colors.white,
                      borderRadius: BorderRadius.circular(12).copyWith(
                        bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                        bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        )
                      ]
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          text,
                          style: const TextStyle(fontSize: 15, color: Colors.black87),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              _buildTickIcon(status),
                            ]
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryBlue,
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
