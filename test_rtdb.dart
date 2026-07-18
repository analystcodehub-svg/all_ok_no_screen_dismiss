import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app');
  try {
    await db.ref('transit/test/test').set({'hello': 'world'});
    print("SUCCESS");
  } catch (e) {
    print("ERROR: $e");
  }
}
