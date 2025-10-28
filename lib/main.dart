import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_dashboard.dart';
import 'screens/otp_screen.dart';
import 'screens/exam_screen.dart';
import 'screens/results_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('examBox');

  // ✅ Initialize authentication token from storage
  await ApiService.initializeAuth();

  // ✅ Run auto-sync at app startup
  await autoSyncPendingExams();

  // ✅ Listen for network reconnect to trigger sync
  Connectivity().onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none) {
      debugPrint('🌐 Network reconnected — syncing pending exams...');
      autoSyncPendingExams();
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Exam App',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final studentId = args?['studentId'] as String? ?? '';
          return StudentDashboard(studentId: studentId);
        },
        '/otp': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final examId = args?['examId'] as String? ?? '';
          final subject = args?['subject'] as String? ?? '';
          final studentId = args?['studentId'] as String? ?? '';
          final expectedOTP = args?['expectedOTP'] as String?;
          final forResults = args?['forResults'] as bool? ?? false;
          final onVerified = args?['onVerified'] as VoidCallback?;

          return OTPScreen(
            examId: examId,
            subject: subject,
            studentId: studentId,
            expectedOTP: expectedOTP,
            forResults: forResults,
            onVerified: onVerified,
          );
        },
        '/exam': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final studentId = args?['studentId'] as String? ?? '';
          final subject = args?['subject'] as String? ?? '';
          final examId = args?['examId'] as String? ?? '';
          final assignmentId = args?['assignmentId'] as String?;
          return ExamScreen(
            studentId: studentId,
            subject: subject,
            examId: examId,
            assignmentId: assignmentId,
          );
        },
        '/results': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ResultsScreen(
            examId: args['examId'],
            studentId: args['studentId'],
          );
        },
      },
    );
  }
}

Future<void> autoSyncPendingExams() async {
  final examBox = Hive.box('examBox');
  final connectivity = await Connectivity().checkConnectivity();

  if (connectivity == ConnectivityResult.none) {
    debugPrint('🚫 No network — skipping auto sync.');
    return;
  }

  debugPrint('🌐 Starting auto-sync for pending exams...');

  for (var exam in examBox.values) {
    if (exam is Map &&
        exam['submitted'] == true &&
        exam['synced'] != true) {
      try {
        final attemptKey = 'attempt_${exam['examId']}_${exam['studentId']}';

        final payload = {
          'studentId': exam['studentId'],
          'examId': exam['examId'],
          'answers': exam['answers'] ?? {},
          'flaggedQuestions': exam['flaggedQuestions'] ?? [],
          'submitted': true,
          'timestamp': DateTime.now().toIso8601String(),
          'questions': exam['questions'] ?? [],
          'score': exam['score'] ?? 0,
          'totalMarks': exam['totalMarks'] ?? 0,
          'correctMarks': exam['correctMarks'] ?? 0,
        };

        debugPrint('📡 Attempting sync for ${exam['examId']} (${exam['studentId']})...');

        final url = Uri.parse('https://yourserver.com/api/exam/submit');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          // ✅ Update same record using consistent key format
          await examBox.put(attemptKey, {
            ...exam,
            'synced': true,
            'lastSyncedAt': DateTime.now().toIso8601String(),
          });

          debugPrint('✅ Auto-sync success for ${exam['examId']}');
        } else {
          debugPrint('❌ Auto-sync failed: ${response.statusCode} for ${exam['examId']}');
        }
      } catch (e) {
        debugPrint('⚠️ Error during auto-sync for ${exam['examId']}: $e');
      }
    }
  }

  debugPrint('🔁 Auto-sync check completed.');
}

