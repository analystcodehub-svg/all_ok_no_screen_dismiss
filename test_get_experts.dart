import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final snap = await FirebaseFirestore.instance.collection('experts').get();
  for (var doc in snap.docs) {
    debugPrint("${doc.id} -> ${doc.data()}");
  }
}
