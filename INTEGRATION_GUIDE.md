# Web Server Integration Guide

## Overview
This guide explains how to connect your Flutter mobile exam app to a web-based exam creation system.

## Architecture

```
[Web Exam System] ←→ REST API ←→ [Flutter Mobile App]
                                        ↓
                                  Local Storage (Hive)
                                  [Offline Support]
```

## Required Backend API Endpoints

Your web server needs to implement these REST API endpoints:

### 1. Authentication

#### `POST /api/auth/login`
Authenticate a student and return their profile.

**Request:**
```json
{
  "studentId": "2021-12345",
  "password": "student_password"
}
```

**Response (200 OK):**
```json
{
  "studentId": "2021-12345",
  "name": "John Doe",
  "email": "john@example.com",
  "token": "jwt_token_here" // optional, for secured endpoints
}
```

### 2. Exam Management

#### `GET /api/exams/available/:studentId`
Get all available exams for a student.

**Response (200 OK):**
```json
[
  {
    "id": "exam01",
    "subject": "Mathematics Final Exam",
    "date": "2025-10-25",
    "duration": 3600,
    "available": true,
    "requiresOtp": true,
    "resultsReleased": false,
    "allowReview": false
  }
]
```

#### `GET /api/exams/:examId/details?studentId=:studentId`
Get detailed exam information (metadata only, not questions).

**Response (200 OK):**
```json
{
  "id": "exam01",
  "subject": "Mathematics Final Exam",
  "instructions": "Answer all questions. No calculator allowed.",
  "duration": 3600,
  "totalQuestions": 50,
  "totalMarks": 100,
  "passingMarks": 50,
  "requiresOtp": true,
  "allowReview": false
}
```

#### `GET /api/exams/:examId/questions`
Get all questions for an exam (only accessible after OTP verification or exam start).

**Response (200 OK):**
```json
[
  {
    "id": "q1",
    "type": "mcq",
    "question": "What is 2 + 2?",
    "choices": ["3", "4", "5", "6"],
    "correct": "4",
    "marks": 1
  },
  {
    "id": "q2",
    "type": "identification",
    "question": "Who invented the telephone?",
    "correct": "Alexander Graham Bell",
    "marks": 2
  },
  {
    "id": "q3",
    "type": "essay",
    "question": "Explain the theory of relativity.",
    "marks": 10
  }
]
```

### 3. OTP Verification

#### `POST /api/exams/:examId/verify-otp`
Verify OTP before allowing exam access.

**Request:**
```json
{
  "studentId": "2021-12345",
  "otp": "123456"
}
```

**Response (200 OK):**
```json
{
  "verified": true,
  "message": "OTP verified successfully"
}
```

**Response (400 Bad Request):**
```json
{
  "verified": false,
  "message": "Invalid or expired OTP"
}
```

### 4. Exam Submission

#### `POST /api/exams/submit`
Submit completed exam answers.

**Request:**
```json
{
  "studentId": "2021-12345",
  "examId": "exam01",
  "answers": {
    "q1": "4",
    "q2": "Alexander Graham Bell",
    "q3": "The theory of relativity..."
  },
  "flaggedQuestions": ["q3"],
  "flaggedSuspicious": false,
  "submitted": true,
  "timestamp": "2025-10-25T14:30:00Z",
  "questions": [...]
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "submissionId": "sub_12345",
  "message": "Exam submitted successfully"
}
```

### 5. Results

#### `GET /api/exams/:examId/results/:studentId`
Get exam results for a student.

**Response (200 OK):**
```json
{
  "examId": "exam01",
  "studentId": "2021-12345",
  "score": 85,
  "totalMarks": 100,
  "percentage": 85,
  "passed": true,
  "submittedAt": "2025-10-25T14:30:00Z",
  "gradedAt": "2025-10-25T16:00:00Z"
}
```

#### `GET /api/exams/completed/:studentId`
Get all completed exams for a student.

**Response (200 OK):**
```json
[
  {
    "examId": "exam01",
    "subject": "Mathematics",
    "score": 85,
    "totalMarks": 100,
    "completedAt": "2025-10-25T14:30:00Z",
    "resultsReleased": true
  }
]
```

### 6. Health Check

#### `GET /api/health`
Check if the server is running.

**Response (200 OK):**
```json
{
  "status": "ok",
  "timestamp": "2025-10-25T12:00:00Z"
}
```

## Implementation Steps

### Step 1: Update API Base URL

Edit `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'https://your-actual-domain.com/api';
```

### Step 2: Update Login Screen

Replace the hardcoded authentication in `login_screen.dart`:

```dart
// OLD CODE (Remove):
if (password == "12345") {
  // hardcoded authentication
}

// NEW CODE (Add):
import '../services/api_service.dart';

Future<void> _login() async {
  final id = _idController.text.trim();
  final password = _passwordController.text.trim();

  if (id.isEmpty || password.isEmpty) {
    // show error
    return;
  }

  setState(() => _isLoading = true);

  // Authenticate with server
  final studentData = await ApiService.authenticateStudent(
    studentId: id,
    password: password,
  );

  setState(() => _isLoading = false);

  if (studentData != null) {
    // Save to Hive
    final box = await Hive.openBox('loginBox');
    if (_rememberMe) {
      await box.put('studentId', id);
      await box.put('token', studentData['token']); // if using JWT
    }

    // Navigate to dashboard
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => StudentDashboard(studentId: id)),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid credentials")),
    );
  }
}
```

### Step 3: Update Student Dashboard

Replace mock data with API calls in `student_dashboard.dart`:

```dart
import '../services/api_service.dart';

// Replace _mockExamData() with:
Future<List<Map<String, dynamic>>> _fetchExamsFromServer() async {
  // Try to fetch from server
  final exams = await ApiService.fetchAvailableExams(
    studentId: widget.studentId,
  );

  if (exams.isNotEmpty) {
    // Cache exams locally
    for (var exam in exams) {
      final metaKey = 'meta_${exam['id']}_${widget.studentId}';
      await examBox.put(metaKey, {
        ...exam,
        'recordType': 'exam',
        'studentId': widget.studentId,
      });
    }
    return exams;
  } else {
    // Fallback to local cache if offline
    return examBox.values
        .where((e) => e is Map && e['recordType'] == 'exam')
        .cast<Map<String, dynamic>>()
        .toList();
  }
}
```

### Step 4: Update Exam Screen

Fetch questions from server in `exam_screen.dart`:

```dart
import '../services/api_service.dart';

@override
void initState() {
  super.initState();
  _loadExamQuestions();
}

Future<void> _loadExamQuestions() async {
  // Try to fetch from server
  final serverQuestions = await ApiService.fetchExamQuestions(
    examId: widget.examId,
  );

  if (serverQuestions.isNotEmpty) {
    setState(() {
      questions.clear();
      questions.addAll(serverQuestions);
    });
    // Cache questions locally
    // ... save to Hive
  } else {
    // Use cached questions if available
    // ... load from Hive
  }
}
```

### Step 5: Update OTP Verification

In `otp_screen.dart`:

```dart
import '../services/api_service.dart';

Future<void> _verifyOTP() async {
  final otp = _otpController.text.trim();
  
  setState(() => _isVerifying = true);

  final verified = await ApiService.verifyExamOTP(
    examId: widget.examId,
    studentId: widget.studentId,
    otp: otp,
  );

  setState(() => _isVerifying = false);

  if (verified) {
    // Allow access to exam
    widget.onVerified?.call();
    Navigator.pop(context);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid OTP")),
    );
  }
}
```

### Step 6: Update Exam Submission

Replace the placeholder submission in `exam_screen.dart`:

```dart
Future<bool> _syncToServer() async {
  final success = await ApiService.submitExam(
    studentId: widget.studentId,
    examId: widget.examId,
    answers: studentAnswers,
    flaggedQuestions: flaggedQuestions.toList(),
    questions: questions,
    flaggedSuspicious: flaggedSuspicious,
  );

  if (success) {
    // Update local storage
    // ... mark as synced in Hive
  }

  return success;
}
```

## Security Considerations

### 1. HTTPS Only
Always use HTTPS for API communication:
```dart
static const String baseUrl = 'https://your-domain.com/api'; // ✅
// NOT: http://your-domain.com/api // ❌
```

### 2. Token Authentication (Optional)
For additional security, implement JWT tokens:

```dart
class ApiService {
  static String? _authToken;

  static void setAuthToken(String token) {
    _authToken = token;
  }

  static Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
  }

  // Use in requests:
  final response = await http.get(url, headers: _getHeaders());
}
```

### 3. Encrypt Sensitive Data
Store sensitive data encrypted in Hive:

```dart
import 'package:hive/hive.dart';

await Hive.openBox('secureBox', encryptionCipher: HiveAesCipher(key));
```

## Testing

### 1. Test with Mock Server
Use a tool like [Mockoon](https://mockoon.com/) or [JSON Server](https://github.com/typicode/json-server) to test locally.

### 2. Test Offline Mode
- Disable internet
- Verify app uses cached data
- Take an exam offline
- Re-enable internet and verify auto-sync works

### 3. Test API Errors
- Test with invalid credentials
- Test with expired OTPs
- Test with network timeouts

## Backend Technology Suggestions

Your web exam system can be built with:

1. **Node.js + Express**
   - Fast, JavaScript-based
   - Easy REST API creation
   - Libraries: `express`, `mongoose`, `jsonwebtoken`

2. **PHP + Laravel**
   - Mature, well-documented
   - Built-in authentication
   - Great for CRUD operations

3. **Python + Django/Flask**
   - Clean syntax
   - Django has built-in admin panel
   - Good for data processing

4. **ASP.NET Core**
   - Enterprise-grade
   - Strong typing
   - Great performance

## Database Schema Example

```sql
-- Students table
CREATE TABLE students (
  id VARCHAR(50) PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100),
  password_hash VARCHAR(255)
);

-- Exams table
CREATE TABLE exams (
  id VARCHAR(50) PRIMARY KEY,
  subject VARCHAR(100),
  instructions TEXT,
  duration INT,
  total_marks INT,
  requires_otp BOOLEAN,
  created_at TIMESTAMP
);

-- Questions table
CREATE TABLE questions (
  id VARCHAR(50) PRIMARY KEY,
  exam_id VARCHAR(50),
  type VARCHAR(20),
  question TEXT,
  choices JSON,
  correct_answer TEXT,
  marks INT,
  FOREIGN KEY (exam_id) REFERENCES exams(id)
);

-- Submissions table
CREATE TABLE submissions (
  id VARCHAR(50) PRIMARY KEY,
  exam_id VARCHAR(50),
  student_id VARCHAR(50),
  answers JSON,
  flagged_questions JSON,
  flagged_suspicious BOOLEAN,
  submitted_at TIMESTAMP,
  score DECIMAL(5,2),
  FOREIGN KEY (exam_id) REFERENCES exams(id),
  FOREIGN KEY (student_id) REFERENCES students(id)
);

-- OTPs table
CREATE TABLE exam_otps (
  exam_id VARCHAR(50),
  otp VARCHAR(10),
  expires_at TIMESTAMP,
  FOREIGN KEY (exam_id) REFERENCES exams(id)
);
```

## Support

For questions or issues, refer to:
- Flutter HTTP package: https://pub.dev/packages/http
- REST API best practices: https://restfulapi.net/
- Hive documentation: https://docs.hivedb.dev/

## Next Steps

1. ✅ Create the API service (already done)
2. 🔧 Set up your web server with the required endpoints
3. 🔧 Update the base URL in `api_service.dart`
4. 🔧 Replace mock data calls with API calls
5. 🧪 Test thoroughly with real server
6. 🚀 Deploy to production
