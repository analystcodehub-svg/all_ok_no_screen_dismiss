import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final snapshot = await FirebaseFirestore.instance.collection('experts').get();
  debugPrint('Total experts: ${snapshot.docs.length}');
  for (var doc in snapshot.docs) {
    debugPrint('${doc.id}: isOnline=${doc.data()['isOnline']}, nickname=${doc.data()['nickname']}');
  }
}
