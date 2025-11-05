import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // 🔧 CHANGE THIS to your actual web server URL
  // For local development:
  //   - Android Emulator: use 'http://10.0.2.2:8000/api'
  //   - iOS Simulator: use 'http://localhost:8000/api'
  //   - Physical Device: use your computer's IP address, e.g., 'http://192.168.1.100:8000/api'
  // For production: use 'https://your-domain.com/api'
  static const String baseUrl = 'https://evelia-unulcerated-keiko.ngrok-free.dev/api';
  
  // Timeout duration for API calls
  static const Duration timeout = Duration(seconds: 10);

  // Authentication token storage
  static String? _authToken;

  /// Set authentication token
  static void setAuthToken(String token) {
    _authToken = token;
  }

  /// Get authentication token
  static String? getAuthToken() {
    return _authToken;
  }

  /// Clear authentication token
  static void clearAuthToken() {
    _authToken = null;
  }

  /// Get headers with authentication
  static Map<String, String> _getHeaders({bool includeAuth = true, bool noCache = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',  // Important for Laravel API
    };
    
    if (includeAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
      debugPrint('🔑 Auth header added to request');
    } else if (includeAuth && _authToken == null) {
      debugPrint('⚠️ No auth token available for request');
    }
    
    // Add cache control headers to prevent caching
    if (noCache) {
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
      headers['Pragma'] = 'no-cache';
      headers['Expires'] = '0';
    }
    
    return headers;
  }

  // ------------------------ AUTHENTICATION ------------------------

  /// Authenticate student with ID and password
  /// Returns {token, user} if successful
  static Future<Map<String, dynamic>?> login({
    required String login,
    required String password,
    String deviceName = 'mobile-app',
  }) async {
    try {
      final url = Uri.parse('$baseUrl/login');
      
      final response = await http.post(
        url,
        headers: _getHeaders(includeAuth: false),
        body: jsonEncode({
          'login': login,
          'password': password,
          'device_name': deviceName,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Store token
        if (data['token'] != null) {
          setAuthToken(data['token']);
          // Also save to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', data['token']);
        }
        debugPrint('✅ Student authenticated: $login');
        return data;
      } else if (response.statusCode == 422) {
        final error = jsonDecode(response.body);
        debugPrint('❌ Authentication failed: ${error['message']}');
        return null;
      } else if (response.statusCode == 403) {
        final error = jsonDecode(response.body);
        debugPrint('❌ Account not active: ${error['message']}');
        return null;
      } else {
        debugPrint('❌ Authentication failed: ${response.statusCode}');
        debugPrint('   Response body: ${response.body}');
        
        // Try to parse error message if JSON
        try {
          final error = jsonDecode(response.body);
          debugPrint('   Error details: ${error['message'] ?? error}');
        } catch (_) {
          // Not JSON, body already logged
        }
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Authentication error: $e');
      return null;
    }
  }

  /// Get current authenticated user info
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final url = Uri.parse('$baseUrl/me');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Fetched current user info');
        return data['user'];
      } else {
        debugPrint('❌ Failed to fetch user info: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching user info: $e');
      return null;
    }
  }

  /// Logout and revoke token
  static Future<bool> logout() async {
    try {
      final url = Uri.parse('$baseUrl/logout');
      
      final response = await http.post(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        debugPrint('✅ Logged out successfully');
        clearAuthToken();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        return true;
      } else {
        debugPrint('❌ Logout failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('⚠️ Logout error: $e');
      return false;
    }
  }

  /// Initialize auth token from storage
  static Future<void> initializeAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        setAuthToken(token);
        debugPrint('✅ Auth token loaded from storage');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading auth token: $e');
    }
  }

  // ------------------------ CLASSES ------------------------

  /// Get enrolled classes for authenticated student
  static Future<List<Map<String, dynamic>>> fetchEnrolledClasses() async {
    try {
      final url = Uri.parse('$baseUrl/classes');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> classes = data['classes'] ?? [];
        debugPrint('✅ Fetched ${classes.length} enrolled classes');
        return classes.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ Failed to fetch classes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching classes: $e');
      return [];
    }
  }

  // ------------------------ EXAMS ------------------------

  /// Fetch all exams assigned to authenticated student
  static Future<List<Map<String, dynamic>>> fetchExams() async {
    try {
      debugPrint('🔗 Connecting to: $baseUrl/exams');
      final url = Uri.parse('$baseUrl/exams');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      debugPrint('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> exams = data['exams'] ?? [];
        debugPrint('✅ Fetched ${exams.length} exams from API');
        debugPrint('═══════════════════════════════════════════════════════════');
        
        // Log each exam with detailed information
        for (int i = 0; i < exams.length; i++) {
          final exam = exams[i];
          debugPrint('📋 EXAM ${i + 1}/${exams.length}:');
          debugPrint('   ├─ Exam ID: ${exam['exam_id']}');
          debugPrint('   ├─ Assignment ID: ${exam['assignment_id']}');
          debugPrint('   ├─ Title: ${exam['title']}');
          debugPrint('   ├─ Subject: ${exam['subject']?['name']} (${exam['subject']?['code']})');
          debugPrint('   ├─ Status: ${exam['status']}');
          debugPrint('   ├─ Duration: ${exam['duration']} minutes');
          debugPrint('   ├─ Schedule Start: ${exam['schedule_start']}');
          debugPrint('   ├─ Schedule End: ${exam['schedule_end']}');
          debugPrint('   ├─ Total Points: ${exam['total_points']}');
          debugPrint('   ├─ No. of Items: ${exam['no_of_items']}');
          debugPrint('   ├─ Requires OTP: ${exam['requiresOtp']}');
          debugPrint('   ├─ Password: ${exam['password']}');
          debugPrint('   ├─ OTP: ${exam['otp']}');
          debugPrint('   ├─ Results Released: ${exam['resultsReleased']}');
          debugPrint('   ├─ Allow Review: ${exam['allowReview']}');
          debugPrint('   ├─ Attempt: ${exam['attempt']}');
          if (exam['attempt'] != null) {
            debugPrint('   │  ├─ Attempt ID: ${exam['attempt']['attempt_id']}');
            debugPrint('   │  ├─ Score: ${exam['attempt']['score']}');
            debugPrint('   │  ├─ Status: ${exam['attempt']['status']}');
            debugPrint('   │  └─ Submitted: ${exam['attempt']['end_time']}');
          }
          debugPrint('   └─ Class: ${exam['class']?['name']} (${exam['class']?['code']})');
          if (i < exams.length - 1) {
            debugPrint('   ───────────────────────────────────────────────────────');
          }
        }
        
        debugPrint('═══════════════════════════════════════════════════════════');
        
        return exams.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ Failed to fetch exams: ${response.statusCode}');
        debugPrint('   Response body: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching exams: $e');
      debugPrint('   Base URL: $baseUrl');
      debugPrint('   Auth token present: ${_authToken != null}');
      return [];
    }
  }

  /// Fetch exam details with questions and sections
  static Future<Map<String, dynamic>?> fetchExamDetails({
    required int examId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/exams/$examId');
      
      debugPrint('🔗 Fetching exam from: $url');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Response content-type: ${response.headers['content-type']}');

      if (response.statusCode == 200) {
        debugPrint('📥 Raw response body length: ${response.body.length}');
        debugPrint('📥 First 500 chars: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        
        // Try to decode the main response
        Map<String, dynamic> data;
        try {
          data = jsonDecode(response.body);
          debugPrint('✅ Successfully decoded main JSON response');
        } catch (e) {
          debugPrint('❌ Failed to decode main JSON response: $e');
          debugPrint('📄 Full response body: ${response.body}');
          return null;
        }
        
        debugPrint('✅ Fetched exam details for exam ID: $examId');
        
        // Debug the data structure
        debugPrint('🔍 Data keys: ${data.keys.toList()}');
        if (data['exam'] != null) {
          debugPrint('🔍 Exam keys: ${data['exam'].keys.toList()}');
        }
        
        // Check if exam data has sections
        if (data['exam'] != null && data['exam']['sections'] != null) {
          debugPrint('📚 Exam has ${data['exam']['sections'].length} sections');
          
          // Pre-process sections to handle string-encoded JSON in options
          try {
            final sections = data['exam']['sections'] as List;
            debugPrint('🔧 Pre-processing ${sections.length} sections...');
            for (var section in sections) {
              if (section['items'] != null) {
                final items = section['items'] as List;
                debugPrint('   Section has ${items.length} items');
                for (var item in items) {
                  debugPrint('   Checking item ${item['item_id']}: options type = ${item['options']?.runtimeType}');
                  // If options is a string, try to decode it
                  if (item['options'] != null && item['options'] is String) {
                    debugPrint('   ✓ Options is a String, will decode');
                    final optionsString = item['options'] as String;
                    
                    // Skip if it's empty or just whitespace
                    if (optionsString.trim().isEmpty) {
                      debugPrint('⚠️ Item ${item['item_id']} has empty options string');
                      item['options'] = null;
                      continue;
                    }
                    
                    try {
                      debugPrint('🔧 Decoding string options for item ${item['item_id']}');
                      debugPrint('   Options string length: ${optionsString.length}');
                      debugPrint('   Options string: ${optionsString.substring(0, optionsString.length > 100 ? 100 : optionsString.length)}...');
                      
                      item['options'] = jsonDecode(optionsString);
                      debugPrint('   ✓ Decoded successfully');
                    } catch (e) {
                      debugPrint('⚠️ Failed to decode options for item ${item['item_id']}: $e');
                      debugPrint('   Full options string: $optionsString');
                      // Set to null so it will be handled gracefully
                      item['options'] = null;
                    }
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error pre-processing sections: $e');
          }
        }
        
        return data;
      } else if (response.statusCode == 404) {
        debugPrint('❌ Exam not found or not accessible');
        return null;
      } else {
        debugPrint('❌ Failed to fetch exam details: ${response.statusCode}');
        debugPrint('   Response body: ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ Error fetching exam details: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      debugPrint('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Verify exam password (OTP)
  /// Returns true if password is verified, false otherwise
  static Future<bool> verifyExamPassword({
    required int examId,
    required int studentId,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/exams/$examId/verify-otp');
      
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('🔐 PASSWORD VERIFICATION REQUEST');
      debugPrint('   URL: $url');
      debugPrint('   Exam ID: $examId');
      debugPrint('   Student ID: $studentId');
      debugPrint('   Password length: ${password.length}');
      debugPrint('   Auth token present: ${_authToken != null}');
      debugPrint('   Timestamp: ${DateTime.now().toIso8601String()}');
      
      final startTime = DateTime.now();
      
      final requestBody = jsonEncode({
        'studentId': studentId,
        'otp': password,
      });
      
      debugPrint('   Request body: ${requestBody.replaceAll(password, "***")}');
      
      final response = await http.post(
        url,
        headers: _getHeaders(noCache: true),
        body: requestBody,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏱️ PASSWORD VERIFICATION TIMED OUT AFTER 5 SECONDS!');
          debugPrint('   This usually means the server is not responding.');
          debugPrint('   Check that Laravel is running: php artisan serve');
          throw Exception('Password verification timed out after 5 seconds');
        },
      );

      final duration = DateTime.now().difference(startTime);
      
      debugPrint('───────────────────────────────────────────────────────────');
      debugPrint('📡 PASSWORD VERIFICATION RESPONSE');
      debugPrint('   Response time: ${duration.inMilliseconds}ms');
      debugPrint('   Status code: ${response.statusCode}');
      debugPrint('   Response body: ${response.body}');
      debugPrint('═══════════════════════════════════════════════════════════');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verified = data['verified'] == true;
        debugPrint('✅ Password verification result: verified=$verified');
        return verified;
      }
      
      debugPrint('❌ Password verification failed with status: ${response.statusCode}');
      return false;
      
    } catch (e) {
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('⚠️ PASSWORD VERIFICATION ERROR');
      debugPrint('   Error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      debugPrint('   Base URL: $baseUrl');
      if (e.toString().contains('timed out')) {
        debugPrint('   💡 TIMEOUT: Server took too long to respond');
        debugPrint('   Check: 1) Is Laravel running? 2) Is the endpoint correct?');
      }
      debugPrint('═══════════════════════════════════════════════════════════');
      return false;
    }
  }

  /// Fetch completed exams for authenticated student
  static Future<List<Map<String, dynamic>>> fetchCompletedExams() async {
    try {
      final url = Uri.parse('$baseUrl/exams/completed');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> completedExams = data['completed_exams'] ?? [];
        debugPrint('✅ Fetched ${completedExams.length} completed exams');
        return completedExams.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ Failed to fetch completed exams: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching completed exams: $e');
      return [];
    }
  }

  // ------------------------ EXAM ATTEMPTS ------------------------

  /// Start a new exam attempt or resume existing one
  static Future<Map<String, dynamic>?> startExamAttempt({
    required int examAssignmentId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/exam-attempts');
      
      final response = await http.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'exam_assignment_id': examAssignmentId,
        }),
      ).timeout(timeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ ${data['message']}');
        return data;
      } else if (response.statusCode == 400) {
        final error = jsonDecode(response.body);
        debugPrint('❌ Cannot start exam: ${error['message']}');
        return {'error': error['message']};
      } else if (response.statusCode == 403) {
        final error = jsonDecode(response.body);
        debugPrint('❌ Access denied: ${error['message']}');
        return {'error': error['message']};
      } else {
        debugPrint('❌ Failed to start exam: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Error starting exam attempt: $e');
      return null;
    }
  }

  /// Submit exam attempt with answers
  static Future<Map<String, dynamic>?> submitExamAttempt({
    required int attemptId,
    required int durationTakenSeconds,
    required List<Map<String, dynamic>> answers,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/exam-attempts/$attemptId/submit');
      
      debugPrint('📤 Submitting attempt $attemptId...');
      debugPrint('   Duration: $durationTakenSeconds seconds');
      debugPrint('   Answers: ${answers.length} items');
      
      final response = await http.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'duration_taken': durationTakenSeconds,
          'answers': answers,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ ${data['message']}');
        if (data['attempt'] != null) {
          debugPrint('   Score: ${data['attempt']['score']}');
          debugPrint('   Status: ${data['attempt']['status']}');
        }
        return data;
      } else if (response.statusCode == 400) {
        final error = jsonDecode(response.body);
        debugPrint('❌ Submission failed: ${error['message']}');
        return {'error': error['message']};
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        final error = jsonDecode(response.body);
        debugPrint('❌ ${error['message']}');
        return {'error': error['message']};
      } else {
        debugPrint('❌ Exam submission failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Error submitting exam: $e');
      return null;
    }
  }

  /// Get exam attempt results
  static Future<Map<String, dynamic>?> fetchExamResults({
    required int attemptId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/exam-attempts/$attemptId/results');
      
      final response = await http.get(
        url,
        headers: _getHeaders(),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Fetched results for attempt: $attemptId');
        return data;
      } else if (response.statusCode == 400) {
        final error = jsonDecode(response.body);
        debugPrint('❌ ${error['message']}');
        return {'error': error['message']};
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        final error = jsonDecode(response.body);
        debugPrint('❌ ${error['message']}');
        return {'error': error['message']};
      } else {
        debugPrint('❌ Failed to fetch results: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching results: $e');
      return null;
    }
  }

  // ------------------------ HELPER METHODS ------------------------

  /// Convert exam item type from Laravel API to app format
  static String convertItemType(String apiType) {
    switch (apiType.toLowerCase()) {
      case 'mcq':
        return 'mcq';
      case 'torf':
        return 'true_false';
      case 'iden':
        return 'identification';
      case 'enum':
        return 'enumeration';
      case 'enum_ordered':
        return 'enumeration';
      case 'enum_unordered':
        return 'enumeration';
      case 'essay':
        return 'essay';
      default:
        return apiType;
    }
  }

  /// Convert exam status from API to user-friendly text
  /// Laravel exam statuses: draft, for approval, approved, on-going, archived
  /// Student attempt statuses: in_progress, submitted
  static String getExamStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'for approval':
        return 'Pending Approval';
      case 'approved':
        return 'Approved';
      case 'on-going':
        return 'On-going';
      case 'archived':
        return 'Archived';
      // Attempt statuses
      case 'in_progress':
        return 'In Progress';
      case 'submitted':
        return 'Submitted';
      default:
        return 'Unknown';
    }
  }

  /// Parse exam from API response to app format
  /// 
  /// Note: Laravel API only sends exams that are:
  /// - Assigned to student's classes
  /// - Status is 'approved' or 'on-going'
  /// 
  /// Student attempt statuses: in_progress, submitted
  static Map<String, dynamic> parseExamForApp(Map<String, dynamic> apiExam) {
    final examStatus = apiExam['status'] ?? 'unknown';
    final attempt = apiExam['attempt'];
    final attemptStatus = attempt?['status'];
    
    // Determine exam availability based on attempt status
    final bool hasCompletedAttempt = attemptStatus == 'submitted';
    final bool hasInProgressAttempt = attemptStatus == 'in_progress';
    
    // Exam is available if:
    // - Status is 'approved' or 'on-going' (already filtered by server)
    // - Student hasn't completed it yet
    // Note: We show approved exams even if not yet in schedule
    final bool isAvailable = !hasCompletedAttempt;
    
    // Check if exam is currently in its scheduled time window
    final bool isInSchedule = _isExamInSchedule(
      apiExam['schedule_start'],
      apiExam['schedule_end'],
    );
    
    debugPrint('📋 Parsing exam: ${apiExam['title']}');
    debugPrint('   Exam Status: $examStatus | Attempt Status: $attemptStatus');
    debugPrint('   In Schedule: $isInSchedule | Available: $isAvailable | Completed: $hasCompletedAttempt');
    debugPrint('   Password from API: password="${apiExam['password']}" | otp="${apiExam['otp']}"');
    
    final extractedPassword = apiExam['password'] ?? apiExam['otp'];
    debugPrint('   Extracted Password: "$extractedPassword"');
    
    return {
      'id': apiExam['exam_id']?.toString() ?? '',
      'assignmentId': apiExam['assignment_id'],
      'examId': apiExam['exam_id'],
      'subject': apiExam['subject']?['name'] ?? 'Unknown Subject',
      'subjectCode': apiExam['subject']?['code'] ?? '',
      'title': apiExam['title'] ?? '',
      'description': apiExam['description'] ?? '',
      'date': apiExam['schedule_start'] ?? '',
      'scheduleStart': apiExam['schedule_start'],
      'scheduleEnd': apiExam['schedule_end'],
      'duration': apiExam['duration'] ?? 0,
      'durationSeconds': apiExam['duration_seconds'] ?? 0,
      'totalPoints': apiExam['total_points'] ?? 0,
      'totalMarks': apiExam['total_points'] ?? 0,
      'noOfItems': apiExam['no_of_items'] ?? 0,
      'examStatus': examStatus,  // Laravel exam status: approved or on-going
      'attemptStatus': attemptStatus,  // Student attempt status: in_progress, submitted
      'status': examStatus,  // Keep for backward compatibility
      'available': isAvailable,  // Can student take this exam? (true if not submitted)
      'inSchedule': isInSchedule,  // Is exam currently in its time window?
      'submitted': hasCompletedAttempt,  // Has student completed this exam?
      'inProgress': hasInProgressAttempt,  // Does student have in-progress attempt?
      'requiresOtp': apiExam['requiresOtp'] ?? false,
      'examPassword': extractedPassword,  // Get password from API
      'resultsReleased': apiExam['resultsReleased'] ?? false,
      'allowReview': apiExam['allowReview'] ?? false,
      'attempt': attempt,
      'attemptId': attempt?['attempt_id'],
      'class': apiExam['class'],
      'synced': hasCompletedAttempt,  // If completed, it's synced with server
    };
  }

  /// Check if exam is currently within its scheduled time window
  static bool _isExamInSchedule(String? scheduleStart, String? scheduleEnd) {
    if (scheduleStart == null || scheduleEnd == null) return false;
    
    try {
      final now = DateTime.now();
      final start = DateTime.parse(scheduleStart);
      final end = DateTime.parse(scheduleEnd);
      
      return now.isAfter(start) && now.isBefore(end);
    } catch (e) {
      debugPrint('⚠️ Error parsing schedule dates: $e');
      return false;
    }
  }

  /// Parse exam questions from API to app format
  static List<Map<String, dynamic>> parseQuestionsForApp(Map<String, dynamic> examData) {
    final List<Map<String, dynamic>> questions = [];
    final sections = examData['exam']?['sections'] as List<dynamic>? ?? [];

    debugPrint('📚 Parsing questions from ${sections.length} sections');

    for (var section in sections) {
      final items = section['items'] as List<dynamic>? ?? [];
      debugPrint('  Section: ${section['title']} (${items.length} items)');
      
      for (var item in items) {
        String? convertedType;
        List<Map<String, String>>? choices;  // Changed to store key-value pairs
        
        try {
          debugPrint('    Processing item ${item['item_id']}...');
          convertedType = convertItemType(item['item_type'] ?? 'mcq');
          dynamic rawOptions = item['options'];
          
          debugPrint('      Raw options type: ${rawOptions.runtimeType}');
          debugPrint('      Raw options value: $rawOptions');
          
          // Parse options - handle different formats from API
          if (rawOptions != null) {
            // First, if it's a string, decode it
            if (rawOptions is String && rawOptions.trim().isNotEmpty) {
              try {
                debugPrint('      Decoding string options: ${rawOptions.substring(0, rawOptions.length > 50 ? 50 : rawOptions.length)}...');
                rawOptions = jsonDecode(rawOptions);
                debugPrint('      Decoded to: ${rawOptions.runtimeType}');
              } catch (e, stackTrace) {
                debugPrint('      ⚠️ Failed to decode options string: $e');
                debugPrint('      Stack: $stackTrace');
                rawOptions = null;
              }
            }
            
            // Now handle the decoded/native format
            // Be very explicit about type checking
            if (rawOptions is String) {
              debugPrint('      ⚠️ Options is still a String after decode attempt!');
              choices = null;
            } else if (rawOptions is List) {
              // Normal array format: ["option1", "option2"]
              // Convert to list of objects with key and value
              debugPrint('      Converting List to choices with keys...');
              choices = [];
              for (int i = 0; i < rawOptions.length; i++) {
                choices.add({
                  'key': String.fromCharCode(65 + i), // A, B, C, D...
                  'text': rawOptions[i].toString(),
                });
              }
            } else if (rawOptions is Map) {
              // Map/object format: {"A": "option1", "B": "option2"} or {"0": "option1", "1": "option2"}
              debugPrint('      Converting Map to choices with keys...');
              final sortedKeys = rawOptions.keys.toList()..sort((a, b) {
                // Try to sort numerically if possible
                final aNum = int.tryParse(a.toString());
                final bNum = int.tryParse(b.toString());
                if (aNum != null && bNum != null) {
                  return aNum.compareTo(bNum);
                }
                return a.toString().compareTo(b.toString());
              });
              choices = [];
              for (var key in sortedKeys) {
                // If keys are numeric, convert to letters
                final displayKey = int.tryParse(key.toString()) != null 
                    ? String.fromCharCode(65 + int.parse(key.toString())) 
                    : key.toString();
                choices.add({
                  'key': displayKey,
                  'text': rawOptions[key].toString(),
                });
              }
              debugPrint('      Map keys order: $sortedKeys');
            } else {
              debugPrint('      ⚠️ Options is unexpected type: ${rawOptions.runtimeType}');
              choices = null;
            }
          }
        } catch (e, stackTrace) {
          debugPrint('      ❌ Error processing item ${item['item_id']}: $e');
          debugPrint('      Stack: $stackTrace');
          continue; // Skip this item and continue with others
        }
        
        debugPrint('    Item ${item['item_id']}: ${item['item_type']} → $convertedType');
        debugPrint('      Question: ${item['question']}');
        debugPrint('      Options parsed: ${choices?.length ?? 0} choices');
        if (choices != null) {
          debugPrint('      Choices: $choices');
        }
        debugPrint('      Points: ${item['points_awarded']}');
        
        // Validate question data
        if (item['question'] == null || item['question'].toString().isEmpty) {
          debugPrint('      ⚠️ WARNING: Empty question text!');
        }
        
        if ((convertedType == 'mcq' || convertedType == 'true_false') && (choices == null || choices.isEmpty)) {
          debugPrint('      ⚠️ WARNING: MCQ/True-False question missing valid options!');
        }
        
        questions.add({
          'id': 'item_${item['item_id']}',
          'itemId': item['item_id'],
          'sectionId': section['section_id'],
          'sectionTitle': section['title'] ?? '',
          'directions': section['directions'] ?? '',
          'type': convertedType,
          'originalType': item['item_type'], // Preserve original server type
          'question': item['question'] ?? '',
          'choices': choices,
          'correct': null, // Not sent from server until submission
          'marks': item['points_awarded'] ?? 1,
          'order': item['order'] ?? 0,
        });
      }
    }

    debugPrint('✅ Parsed ${questions.length} questions total');
    
    // Validate all questions have required fields
    for (var q in questions) {
      if (q['id'] == null) debugPrint('❌ Question missing id!');
      if (q['type'] == null) debugPrint('❌ Question missing type!');
      if (q['question'] == null) debugPrint('❌ Question missing question text!');
    }
    
    return questions;
  }

  /// Format answers from app to API format for submission
  static List<Map<String, dynamic>> formatAnswersForSubmission(
    Map<String, dynamic> appAnswers,
    List<Map<String, dynamic>> questions,
  ) {
    final List<Map<String, dynamic>> formattedAnswers = [];

    for (var question in questions) {
      final itemId = question['itemId'];
      final answerId = question['id'];
      final answer = appAnswers[answerId];

      if (answer != null && answer.toString().isNotEmpty) {
        formattedAnswers.add({
          'item_id': itemId,
          'answer': question['type'] == 'true_false' && answer is bool
              ? (answer ? 'True' : 'False')
              : answer.toString(),
        });
      }
    }

    return formattedAnswers;
  }

  // ------------------------ HEALTH CHECK ------------------------

  /// Check if the server is reachable
  static Future<bool> checkServerHealth() async {
    try {
      final url = Uri.parse('$baseUrl/health');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Server health: ${data['status']}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Server health check failed: $e');
      return false;
    }
  }
}
