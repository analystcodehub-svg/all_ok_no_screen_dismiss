import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, 'yaster_chat.db');
  final db = await openDatabase(path);
  final rows = await db.query('call_logs');
  print('CALL LOGS: $rows');
}
