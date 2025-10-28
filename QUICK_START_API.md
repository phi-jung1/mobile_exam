# Quick Start: Integrating Laravel API with Flutter App

## 1. Update Base URL

Edit `lib/services/api_service.dart` line 8:

```dart
static const String baseUrl = 'http://localhost/exam1/public/api';
// or for production:
// static const String baseUrl = 'https://your-domain.com/api';
```

## 2. Initialize Auth on App Start

Update `lib/main.dart`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('examBox');
  
  // Initialize authentication token
  await ApiService.initializeAuth();

  // ... rest of your code
  runApp(const MyApp());
}
```

## 3. Update Login Screen

Replace the login logic in `lib/screens/login_screen.dart`:

```dart
import '../services/api_service.dart';

Future<void> _login() async {
  final id = _idController.text.trim();
  final password = _passwordController.text.trim();

  if (id.isEmpty || password.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please enter both ID and Password")),
    );
    return;
  }

  setState(() => _isLoading = true);

  // Call API login
  final result = await ApiService.login(
    login: id,
    password: password,
  );

  setState(() => _isLoading = false);

  if (result != null && result['token'] != null) {
    // Save user info to Hive
    try {
      final box = await Hive.openBox('loginBox');
      if (_rememberMe) {
        await box.put('studentId', id);
        await box.put('user', result['user']);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Welcome, ${result['user']['first_name']}!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StudentDashboard(
            studentId: result['user']['id_number'],
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error saving login info: $e");
    }
  } else {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid credentials or account not active")),
    );
  }
}
```

## 4. Update Student Dashboard to Fetch Real Exams

Replace `_mockExamData()` in `lib/screens/student_dashboard.dart`:

```dart
import '../services/api_service.dart';

// Replace _mockExamData() with:
Future<List<Map<String, dynamic>>> _fetchExamsFromServer() async {
  try {
    // Fetch exams from API
    final apiExams = await ApiService.fetchExams();
    
    if (apiExams.isEmpty) {
      // Fallback to cached exams if API fails
      return _loadCachedExams();
    }

    // Parse and cache exams
    final parsedExams = <Map<String, dynamic>>[];
    
    for (var apiExam in apiExams) {
      final exam = ApiService.parseExamForApp(apiExam);
      parsedExams.add(exam);
      
      // Cache to Hive
      final metaKey = 'meta_${exam['examId']}_${widget.studentId}';
      await examBox.put(metaKey, {
        ...exam,
        'recordType': 'exam',
        'studentId': widget.studentId,
      });
    }

    return parsedExams;
  } catch (e) {
    debugPrint('Error fetching exams: $e');
    return _loadCachedExams();
  }
}

List<Map<String, dynamic>> _loadCachedExams() {
  return examBox.values
      .where((e) => e is Map && 
             e['recordType'] == 'exam' && 
             e['studentId'] == widget.studentId)
      .cast<Map<String, dynamic>>()
      .toList();
}

// Update _initHive() to use _fetchExamsFromServer()
Future<void> _initHive() async {
  examBox = await Hive.openBox('examBox');
  
  // Fetch from server
  await _fetchExamsFromServer();
  
  setState(() {}); // refresh UI
}
```

## 5. Update OTP Verification Screen

Update `lib/screens/otp_screen.dart`:

```dart
import '../services/api_service.dart';

Future<void> _verifyOTP() async {
  final otp = _otpController.text.trim();
  
  if (otp.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please enter the exam password")),
    );
    return;
  }

  setState(() => _isVerifying = true);

  // Get student ID from user data (you need to pass this from login)
  final prefs = await SharedPreferences.getInstance();
  final userJson = prefs.getString('user');
  final user = userJson != null ? jsonDecode(userJson) : null;
  final studentId = user?['student_id'] ?? 0;

  final result = await ApiService.verifyExamPassword(
    examId: int.parse(widget.examId),
    studentId: studentId,
    password: otp,
  );

  setState(() => _isVerifying = false);

  if (result != null && result['verified'] == true) {
    // Password correct
    widget.onVerified?.call();
    if (mounted) Navigator.pop(context);
  } else {
    // Password wrong
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result?['message'] ?? "Invalid exam password"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

## 6. Update Exam Screen to Fetch Questions

Update `lib/screens/exam_screen.dart`:

```dart
import '../services/api_service.dart';

@override
void initState() {
  super.initState();
  _loadExamFromServer();
  // ... rest of init
}

Future<void> _loadExamFromServer() async {
  try {
    // Fetch exam details with questions
    final examData = await ApiService.fetchExamDetails(
      examId: int.parse(widget.examId),
    );

    if (examData != null && examData['exam'] != null) {
      // Parse questions
      final parsedQuestions = ApiService.parseQuestionsForApp(examData);
      
      setState(() {
        questions.clear();
        questions.addAll(parsedQuestions);
      });

      // Initialize focus nodes for text fields
      for (var q in questions) {
        if (q['type'] == 'identification' || 
            q['type'] == 'enumeration' || 
            q['type'] == 'essay') {
          _focusNodes[q['id']] = FocusNode();
        }
      }

      // Shuffle questions if needed
      questions.shuffle();
      
      // Cache questions locally
      examBox.put('questions_${widget.examId}', questions);
    } else {
      // Load from cache if API fails
      final cached = examBox.get('questions_${widget.examId}');
      if (cached != null) {
        setState(() {
          questions.clear();
          questions.addAll(List<Map<String, dynamic>>.from(cached));
        });
      }
    }
  } catch (e) {
    debugPrint('Error loading exam: $e');
    // Try loading from cache
  }
}
```

## 7. Update Exam Submission

Update the `submitExam()` method in `exam_screen.dart`:

```dart
Future<void> submitExam({bool autoSubmitted = false}) async {
  if (!mounted) return;
  setState(() => syncing = true);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  // Start exam attempt first (if not already started)
  final attemptData = await ApiService.startExamAttempt(
    examAssignmentId: int.parse(widget.examId), // Use assignment_id from exam data
  );

  if (attemptData == null || attemptData['error'] != null) {
    if (mounted) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(attemptData?['error'] ?? 'Failed to start attempt')),
    );
    setState(() => syncing = false);
    return;
  }

  final attemptId = attemptData['attempt']['attempt_id'];

  // Format answers for API
  final formattedAnswers = ApiService.formatAnswersForSubmission(
    studentAnswers,
    questions,
  );

  // Submit to server
  final result = await ApiService.submitExamAttempt(
    attemptId: attemptId,
    answers: formattedAnswers,
  );

  if (result != null && result['attempt'] != null) {
    // Submission successful
    final attempt = result['attempt'];
    
    // Update local storage
    await markExamCompleted(
      widget.examId,
      studentAnswers,
      attemptId: attemptId,
    );

    setState(() {
      syncing = false;
      submitted = true;
    });

    if (mounted && Navigator.canPop(context)) Navigator.pop(context);

    // Show success dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(autoSubmitted ? "Exam Auto-Submitted" : "Exam Submitted"),
        content: Text(
          autoSubmitted
              ? "The exam was auto-submitted after multiple exits."
              : "Your exam has been successfully submitted.\nScore: ${attempt['score']}/${attempt['total_points'] ?? 'N/A'}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              navigateWithFade(
                context,
                StudentDashboard(studentId: widget.studentId),
              );
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  } else {
    // Submission failed - save locally for later sync
    await markExamCompleted(widget.examId, studentAnswers);
    
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    
    setState(() => syncing = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved locally. Will sync when online.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
```

## 8. Fetch Results

Create a method to fetch and display results:

```dart
Future<void> _fetchAndShowResults(int attemptId) async {
  final results = await ApiService.fetchExamResults(attemptId: attemptId);
  
  if (results != null && results['attempt'] != null) {
    final attempt = results['attempt'];
    final exam = results['exam'];
    
    // Show results dialog or navigate to results screen
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${exam['title']} Results'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Score: ${attempt['score']}/${attempt['total_points']}'),
            Text('Percentage: ${attempt['percentage'].toStringAsFixed(2)}%'),
            Text('Status: ${attempt['status']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
```

## 9. Add Logout Functionality

Add a logout button in your dashboard:

```dart
Future<void> _logout() async {
  final success = await ApiService.logout();
  
  if (success) {
    // Clear local data
    final box = await Hive.openBox('loginBox');
    await box.clear();
    
    // Navigate to login
    Navigator.pushReplacementNamed(context, '/login');
  }
}
```

## 10. Handle API Errors

Add error handling wrapper:

```dart
Future<T?> handleApiCall<T>(
  Future<T?> Function() apiCall,
  String errorMessage,
) async {
  try {
    return await apiCall();
  } catch (e) {
    debugPrint('API Error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage)),
    );
    return null;
  }
}

// Usage:
final exams = await handleApiCall(
  () => ApiService.fetchExams(),
  'Failed to load exams',
);
```

## Testing Checklist

- [ ] Update base URL in `api_service.dart`
- [ ] Test login with valid credentials
- [ ] Test login with invalid credentials
- [ ] Verify token is saved after login
- [ ] Test fetching exams list
- [ ] Test OTP/password verification
- [ ] Test loading exam questions
- [ ] Test submitting exam answers
- [ ] Test fetching results
- [ ] Test logout functionality
- [ ] Test offline mode (airplane mode)
- [ ] Test auto-sync when coming back online

## Common Issues

**401 Unauthorized:**
- Token not included in request
- Token expired - need to re-login

**403 Forbidden:**
- Student not enrolled in the class
- Exam not assigned to student

**Network Errors:**
- Check base URL is correct
- Verify server is running
- Check internet connection

## Next Steps

1. Update base URL
2. Test login flow
3. Test exam flow end-to-end
4. Implement proper error handling
5. Add loading states
6. Test offline functionality
7. Deploy to production server
