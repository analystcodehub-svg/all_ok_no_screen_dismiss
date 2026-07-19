import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalChatDatabase {
  static final LocalChatDatabase instance = LocalChatDatabase._init();
  static Database? _database;

  // We use a StreamController to broadcast changes to listeners (like the ChatListScreen)
  final StreamController<void> _updateController = StreamController<void>.broadcast();

  Stream<void> get updates => _updateController.stream;

  LocalChatDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chat_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 3, // Upgraded for call logs with names
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE call_logs (
              logId TEXT PRIMARY KEY,
              callerId TEXT NOT NULL,
              receiverId TEXT NOT NULL,
              durationSeconds INTEGER NOT NULL,
              status TEXT NOT NULL,
              timestamp INTEGER NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_call_timestamp ON call_logs (timestamp DESC)');
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE call_logs ADD COLUMN otherUserName TEXT');
          } catch (e) {
            debugPrint('Error altering call_logs table: $e');
          }
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        msgId TEXT PRIMARY KEY,
        roomId TEXT NOT NULL,
        senderId TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        status INTEGER NOT NULL
      )
    ''');
    // Index to speed up roomId queries
    await db.execute('CREATE INDEX idx_roomId ON messages (roomId)');

    await db.execute('''
      CREATE TABLE call_logs (
        logId TEXT PRIMARY KEY,
        callerId TEXT NOT NULL,
        receiverId TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        otherUserName TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_call_timestamp ON call_logs (timestamp DESC)');
  }

  // Generate a deterministic room ID using double-underscore separator
  // so UIDs that contain underscores are not split incorrectly.
  static String generateRoomId(String uid1, String uid2) {
    final users = [uid1, uid2];
    users.sort();
    return users.join('__');
  }

  // Extract other user ID from room ID
  static String getOtherUserIdFromRoomId(String roomId, String myUid) {
    // Split on double-underscore only
    final parts = roomId.split('__');
    if (parts.length == 2) {
      return parts[0] == myUid ? parts[1] : parts[0];
    }
    // Legacy fallback: single underscore (old room IDs)
    final idx = roomId.indexOf(myUid);
    if (idx == 0) {
      // myUid is at the start, other is after myUid + '_'
      final rest = roomId.substring(myUid.length);
      if (rest.startsWith('_')) return rest.substring(1);
    } else if (idx > 0) {
      // myUid is at the end
      final rest = roomId.substring(0, idx);
      if (rest.endsWith('_')) return rest.substring(0, rest.length - 1);
    }
    return '';
  }

  Future<void> saveMessageLocally(Map<String, dynamic> message) async {
    final db = await instance.database;
    await db.insert(
      'messages',
      message,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _updateController.add(null);
  }

  Future<void> updateMessageStatus(String msgId, int newStatus) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'status': newStatus},
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
    _updateController.add(null);
  }

  Future<List<Map<String, dynamic>>> fetchChatHistory(String roomId) async {
    final db = await instance.database;
    return await db.query(
      'messages',
      where: 'roomId = ?',
      whereArgs: [roomId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getUnreadMessages(String roomId, String senderId) async {
    final db = await instance.database;
    return await db.query(
      'messages',
      where: 'roomId = ? AND senderId = ? AND status < 3',
      whereArgs: [roomId, senderId],
    );
  }

  // getRecentChats for ChatListScreen
  Future<List<Map<String, dynamic>>> getRecentChats(String myUid) async {
    final db = await instance.database;
    
    // Query to get the latest message for each room, plus count unread messages from the OTHER person
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT 
        m1.roomId,
        m1.text as lastMessage,
        m1.timestamp,
        m1.senderId as lastSenderId,
        (
          SELECT COUNT(*) 
          FROM messages m2 
          WHERE m2.roomId = m1.roomId 
            AND m2.senderId != ? 
            AND m2.status < 3
        ) as unreadCount
      FROM messages m1
      INNER JOIN (
          SELECT roomId, MAX(timestamp) as maxTime
          FROM messages
          GROUP BY roomId
      ) grouped_m ON m1.roomId = grouped_m.roomId AND m1.timestamp = grouped_m.maxTime
      ORDER BY m1.timestamp DESC
    ''', [myUid]);

    // Enhance the result with otherUserId
    return result.map((row) {
      final mutableRow = Map<String, dynamic>.from(row);
      mutableRow['otherUserId'] = getOtherUserIdFromRoomId(row['roomId'] as String, myUid);
      return mutableRow;
    }).toList();
  }

  Future<void> saveCallLogLocally(Map<String, dynamic> log) async {
    final db = await instance.database;
    await db.insert(
      'call_logs',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _updateController.add(null);
  }

  Future<List<Map<String, dynamic>>> getRecentCallLogs(String myId) async {
    final db = await instance.database;
    return await db.query(
      'call_logs',
      where: 'callerId = ? OR receiverId = ?',
      whereArgs: [myId, myId],
      orderBy: 'timestamp DESC',
    );
  }

  // Sync last 50 call logs from Firestore (Only once per install/login)
  Future<void> syncCallLogsFromFirestore(String myId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSynced = prefs.getBool('has_synced_call_logs_$myId') ?? false;

      if (hasSynced) {
        return; // Already synced once
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('call_logs')
          .where(Filter.or(
            Filter('callerId', isEqualTo: myId),
            Filter('receiverId', isEqualTo: myId),
          ))
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final db = await instance.database;
        final batch = db.batch();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          batch.insert(
            'call_logs',
            {
              'logId': doc.id,
              'callerId': data['callerId'] ?? '',
              'receiverId': data['receiverId'] ?? '',
              'durationSeconds': data['durationSeconds'] ?? 0,
              'status': data['status'] ?? 'unknown',
              'timestamp': data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
              'otherUserName': data['otherUserName'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
        _updateController.add(null);
      }
      
      // Mark as synced
      await prefs.setBool('has_synced_call_logs_$myId', true);
    } catch (e) {
      debugPrint('Error syncing call logs: $e');
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
