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

// ✅ ADDED: API Configuration
class ApiConfig {
  static const String baseUrl = 'https://yourserver.com';
  static const String submitEndpoint = '/api/exam/submit';
  static const Duration syncTimeout = Duration(seconds: 10);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Hive.initFlutter();
    await Hive.openBox('examBox');
    
    // ✅ Initialize authentication token from storage
    await ApiService.initializeAuth();
    
    // ✅ Run auto-sync at app startup with error handling
    await autoSyncPendingExams();
    
    // ✅ FIXED: Listen for network reconnect with error handling and debouncing
    DateTime? lastSyncAttempt;
    Connectivity().onConnectivityChanged.listen((results) {
      try {
        final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
        
        if (result != ConnectivityResult.none) {
          // ✅ Debounce sync attempts (prevent rapid retries)
          final now = DateTime.now();
          if (lastSyncAttempt != null && 
              now.difference(lastSyncAttempt!).inSeconds < 30) {
            debugPrint('🚫 Skipping sync - too soon since last attempt');
            return;
          }
          
          lastSyncAttempt = now;
          debugPrint('🌐 Network reconnected — syncing pending exams...');
          
          // ✅ Run sync in separate zone to catch errors
          autoSyncPendingExams().catchError((error) {
            debugPrint('⚠️ Auto-sync error on reconnect: $error');
          });
        }
      } catch (e) {
        debugPrint('⚠️ Error in connectivity listener: $e');
      }
    });
    
    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint('❌ Fatal error during app initialization: $e');
    debugPrint('Stack trace: $stackTrace');
    
    // ✅ Show error screen instead of crashing
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    ));
  }
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
          final studentName = args?['studentName'] as String?;
          
          // ✅ ADDED: Validation
          if (studentId.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/login');
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          return StudentDashboard(
            studentId: studentId,
            studentName: studentName,
          );
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
          
          // ✅ ADDED: Validation
          if (studentId.isEmpty || examId.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/dashboard', arguments: {
                'studentId': studentId,
              });
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
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
            examTitle: args['examTitle'],
            subject: args['subject'],
          );
        },
      },
    );
  }
}

// ✅ IMPROVED: Better error handling and timeout management
Future<void> autoSyncPendingExams() async {
  try {
    final examBox = Hive.box('examBox');
    final connectivity = await Connectivity().checkConnectivity();
    final result = connectivity.isNotEmpty ? connectivity.first : ConnectivityResult.none;

    if (result == ConnectivityResult.none) {
      debugPrint('🚫 No network — skipping auto sync.');
      return;
    }

    debugPrint('🌐 Starting auto-sync for pending exams...');

    // ✅ ADDED: Track sync statistics
    int successCount = 0;
    int failureCount = 0;
    int skippedCount = 0;

    for (var exam in examBox.values) {
      if (exam is! Map) {
        skippedCount++;
        continue;
      }

      if (exam['submitted'] == true && exam['synced'] != true) {
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

          // ✅ FIXED: Use config constant and better timeout
          final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.submitEndpoint}');
          final response = await http
              .post(
                url,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: jsonEncode(payload),
              )
              .timeout(
                ApiConfig.syncTimeout,
                onTimeout: () {
                  debugPrint('⏱️ Sync timeout for ${exam['examId']}');
                  return http.Response('{"error": "timeout"}', 408);
                },
              );

          if (response.statusCode == 200) {
            // ✅ Update same record using consistent key format
            await examBox.put(attemptKey, {
              ...exam,
              'synced': true,
              'lastSyncedAt': DateTime.now().toIso8601String(),
            });

            debugPrint('✅ Auto-sync success for ${exam['examId']}');
            successCount++;
          } else {
            debugPrint('❌ Auto-sync failed: ${response.statusCode} for ${exam['examId']}');
            failureCount++;
            
            // ✅ ADDED: Mark with retry count
            final retryCount = (exam['syncRetryCount'] ?? 0) + 1;
            await examBox.put(attemptKey, {
              ...exam,
              'syncRetryCount': retryCount,
              'lastSyncAttempt': DateTime.now().toIso8601String(),
            });
          }
        } catch (e) {
          debugPrint('⚠️ Error during auto-sync for ${exam['examId']}: $e');
          failureCount++;
        }
      } else {
        skippedCount++;
      }
    }

    debugPrint('🔁 Auto-sync completed:');
    debugPrint('   ✅ Success: $successCount');
    debugPrint('   ❌ Failed: $failureCount');
    debugPrint('   ⏭️ Skipped: $skippedCount');
  } catch (e, stackTrace) {
    debugPrint('❌ Fatal error in autoSyncPendingExams: $e');
    debugPrint('Stack trace: $stackTrace');
  }
}