import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'package:mo_be/screens/student_dashboard.dart';

/// Navigate to dashboard with proper name handling
/// Automatically loads student name from Hive if not provided
Future<void> navigateToDashboard(
  BuildContext context, 
  String studentId, {
  String? studentName,
}) async {
  // ✅ If name not provided, try to load from Hive
  String? finalName = studentName;
  
  if (finalName == null || finalName.isEmpty) {
    try {
      final box = await Hive.openBox('loginBox');
      final userJson = box.get('user');
      
      if (userJson != null && userJson is String) {
        final user = jsonDecode(userJson);
        final firstName = user['first_name'] ?? '';
        final lastName = user['last_name'] ?? '';
        finalName = '$firstName $lastName'.trim();
        
        if (finalName.isNotEmpty) {
          debugPrint('✅ Loaded student name from Hive: $finalName');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not load student name from Hive: $e');
    }
  }
  
  if (!context.mounted) return;
  
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          StudentDashboard(
            studentId: studentId,
            studentName: finalName, // ✅ Pass the name
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 600),
    ),
    (route) => false,
  );
}