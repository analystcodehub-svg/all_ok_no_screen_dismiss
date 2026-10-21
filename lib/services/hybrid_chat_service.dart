import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_chat_database.dart';
import 'block_service.dart';
import 'user_database_service.dart';

class HybridChatService {
  static final HybridChatService instance = HybridChatService._init();
  static String? activeChatRoomId;
  static void Function(double earnedAmount)? onLiveMessageEarned;
  static bool? isFemaleUser;
  
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  StreamSubscription? _messagesSub;
  StreamSubscription? _acksSub;

  String? _initializedUid;

  HybridChatService._init();

  /// Start listening to temporary routing queues
  void initListeners(String myUid) {
    if (myUid.isEmpty) return; // Do not listen to root nodes

    // If already initialized for this UID with active subs, return
    if (_messagesSub != null && _acksSub != null && _initializedUid == myUid) return;
    
    // If initialized for a different UID, cancel old listeners
    dispose();
    
    _initializedUid = myUid;
    _listenToIncomingMessages(myUid);
    _listenToIncomingAcks(myUid);
  }

  void dispose() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _acksSub?.cancel();
    _acksSub = null;
    _initializedUid = null;
  }

  /// Sends a message: Saves locally (status 1) and pushes to RTDB transit
  Future<void> sendMessage({
    required String roomId,
    required String senderUid,
    required String receiverUid,
    required String text,
  }) async {
    final msgId = _database.ref().push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final message = {
      'msgId': msgId,
      'roomId': roomId,
      'senderId': senderUid,
      'text': text,
      'timestamp': timestamp,
    };

    // 1. Save locally (status 1: Sent - Single Grey Tick, isEarned: 0)
    await LocalChatDatabase.instance.saveMessageLocally({
      ...message,
      'status': 1,
      'isEarned': 0,
    });

    // 2. Push to transit (pure message data, deleted immediately upon arrival)
    await _database.ref('transit/messages/$receiverUid/$msgId').set(message);
  }

  /// Manually mark an existing unread message as read (when user opens chat)
  Future<void> markAsRead(String msgId, String senderUid, String myUid) async {
    // 1. Update local SQLite status to 3 (Read)
    await LocalChatDatabase.instance.updateMessageStatus(msgId, 3);

    // 2. Push Read ACK (status 3 = Double Blue Tick) back to sender
    await _pushAck(
      receiverUid: senderUid,
      msgId: msgId,
      status: 3,
    );
  }

  Future<void> _pushAck({
    required String receiverUid,
    required String msgId,
    required int status,
  }) async {
    try {
      await _database.ref('transit/acks/$receiverUid/$msgId').set({
        'status': status,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Error pushing ACK: $e');
    }
  }

  void _listenToIncomingMessages(String myUid) {
    _messagesSub = _database.ref('transit/messages/$myUid').onChildAdded.listen((event) async {
      if (event.snapshot.value == null) return;

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final msgId = data['msgId'] as String? ?? event.snapshot.key!;
      final roomId = data['roomId'] as String;
      final senderId = data['senderId'] as String;

      // Ensure we immediately delete from RTDB to maintain zero storage cost
      await event.snapshot.ref.remove().catchError((_) {});

      // Check if this sender is blocked
      if (BlockService.instance.isBlocked(senderId)) {
        debugPrint('Blocked message dropped from: $senderId');
        return; // Drop the message entirely
      }

      // Determine status based on active screen
      // If currently inside this chat room -> 3 (Read / Blue tick)
      // If not currently in this chat room -> 2 (Delivered / Double grey tick)
      final bool isLive = (activeChatRoomId == roomId);
      final int localStatus = isLive ? 3 : 2;
      int isEarned = 0;

      // Female earns 10 paise on incoming message ONLY in live chat!
      // No earning on transit/background messages or unread backlog messages
      if (isLive && senderId != myUid) {
        bool isFemale = isFemaleUser ?? false;
        if (!isFemale) {
          try {
            final prefs = await SharedPreferences.getInstance();
            isFemale = (prefs.getString('userRole')?.toLowerCase() == 'female');
          } catch (_) {}
        }

        if (isFemale) {
          isEarned = 1;
          // Atomically update expert wallet in RTDB
          await UserDatabaseService.instance.incrementExpertStats(
            myUid,
            earned: 0.10,
            seconds: 0,
            minutesToAdd: 0,
          );
          // Notify active screen/AppState
          onLiveMessageEarned?.call(0.10);
        }
      }

      // 1. Save to local SQLite
      data['status'] = localStatus;
      data['isEarned'] = isEarned;
      await LocalChatDatabase.instance.saveMessageLocally(data);

      // 2. Send acknowledgment back to sender!
      await _pushAck(
        receiverUid: senderId,
        msgId: msgId,
        status: localStatus,
      );
    }, onError: (e) {
      debugPrint('Error listening to incoming messages: $e');
    });
  }

  void _listenToIncomingAcks(String myUid) {
    _acksSub = _database.ref('transit/acks/$myUid').onChildAdded.listen((event) async {
      if (event.snapshot.value == null) return;

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final msgId = event.snapshot.key!;
      final newStatus = (data['status'] as num?)?.toInt() ?? 2;

      // Ensure immediate deletion from RTDB
      await event.snapshot.ref.remove().catchError((_) {});

      // Update local message status (1 -> 2, or 2 -> 3)
      await LocalChatDatabase.instance.updateMessageStatus(msgId, newStatus);
    }, onError: (e) {
      debugPrint('Error listening to incoming ACKs: $e');
    });
  }
}
