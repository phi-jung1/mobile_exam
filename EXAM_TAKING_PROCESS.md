# Exam Taking Process Documentation

This document describes the complete flow of taking an exam in the mobile app, from fetching available exams to submitting answers.

---

## Overview

The exam taking process involves several screens and API interactions:

1. **Authentication** - Student logs in and receives auth token
2. **Exam List** - Student views available and completed exams
3. **Exam Start** - Student starts an exam attempt on the server
4. **Question Loading** - App fetches exam questions from API
5. **Answering** - Student answers questions (stored locally)
6. **Submission** - Student submits exam with all answers to server
7. **Results** - Student views their score

---

## 1. Authentication Flow

### Login Screen (`lib/screens/login_screen.dart`)

**Process:**
```dart
1. Student enters ID and password
2. App calls: POST /api/login
3. API Response: { token: "...", user: {...} }
4. App stores token: ApiService.setAuthToken(token)
5. App saves token to Hive: loginBox.put('authToken', token)
6. Navigate to Student Dashboard
```

**Key Code:**
```dart
final result = await ApiService.login(
  login: id,
  password: password,
);

if (result != null && result['token'] != null) {
  ApiService.setAuthToken(result['token']);
  await box.put('authToken', result['token']);
  // Navigate to dashboard
}
```

**API Endpoint:**
- `POST /api/login`
- Body: `{ "login": "student_id", "password": "password" }`
- Response: `{ "token": "Bearer token...", "user": {...} }`

---

## 2. Fetching Exams

### Student Dashboard (`lib/screens/student_dashboard.dart`)

**Process:**
```dart
1. Dashboard initializes → _initHive()
2. Restore auth token from Hive storage
3. Call: GET /api/exams (with Bearer token)
4. API returns list of exams with status
5. Parse each exam with parseExamForApp()
6. Cache exams locally in Hive
7. Display available and completed exams
```

**Key Code:**
```dart
// Restore token
final loginBox = await Hive.openBox('loginBox');
final savedToken = loginBox.get('authToken');
ApiService.setAuthToken(savedToken);

// Fetch exams
final apiExams = await ApiService.fetchExams();

for (var apiExam in apiExams) {
  final exam = ApiService.parseExamForApp(apiExam);
  await examBox.put(metaKey, exam);
}
```

**API Endpoint:**
- `GET /api/exams`
- Headers: `Authorization: Bearer {token}`
- Response: Array of exam objects with status

**Exam Status Values:**
- `available` - Exam can be taken
- `in_progress` - Exam started but not completed
- `completed` - Exam submitted
- Other statuses are parsed as unavailable

**Exam Data Structure (from API):**
```json
{
  "exam_id": 9,
  "assignment_id": 123,
  "title": "Midterm Exam",
  "subject": { "code": "CS101", "name": "Programming" },
  "schedule_start": "2025-10-24T09:00:00Z",
  "schedule_end": "2025-10-24T11:00:00Z",
  "duration": 60,
  "status": "available",
  "requiresOtp": false,
  "attempt": null
}
```

**Parsed Exam Structure (for app):**
```dart
{
  'id': '9',
  'examId': 9,
  'assignmentId': 123,
  'title': 'Midterm Exam',
  'subject': 'Programming',
  'subjectCode': 'CS101',
  'duration': 60,
  'available': true,
  'submitted': false,
  'requiresOtp': false,
  'status': 'available'
}
```

---

## 3. Starting an Exam Attempt

### Exam Screen Initialization (`lib/screens/exam_screen.dart`)

**Navigation Parameters:**
```dart
Navigator.pushNamed(context, '/exam', arguments: {
  'studentId': '12345',
  'examId': '9',
  'assignmentId': '123',  // Important: assignment_id from API
  'examTitle': 'Midterm Exam',
  'subject': 'Programming'
});
```

**Process Flow:**
```dart
1. ExamScreen.initState()
2. _loadExamQuestions() - Fetch questions from API
3. _checkForUnfinishedExam() - Check for existing attempt
4. _startExamAttempt() - Create attempt on server
5. API returns: { attempt: { attempt_id, start_time } }
6. Store attemptId and attemptStartTime
7. saveLocalData() - Cache attempt info
8. _startExamNormally() - Initialize timer and UI
```

**Key Code - Start Attempt:**
```dart
Future<void> _startExamAttempt() async {
  final assignmentId = int.parse(widget.assignmentId ?? widget.examId);
  
  final result = await ApiService.startExamAttempt(
    examAssignmentId: assignmentId,
  );
  
  if (result['attempt'] != null) {
    attemptId = result['attempt']['attempt_id'];
    attemptStartTime = DateTime.parse(result['attempt']['start_time']);
    saveLocalData();
  }
}
```

**API Endpoint:**
- `POST /api/exam-attempts`
- Headers: `Authorization: Bearer {token}`
- Body: `{ "exam_assignment_id": 123 }`
- Response:
```json
{
  "attempt": {
    "attempt_id": 456,
    "exam_assignment_id": 123,
    "student_id": 789,
    "start_time": "2025-10-24T09:00:00.000000Z",
    "status": "in_progress"
  },
  "message": "Exam attempt started successfully"
}
```

**Resume Existing Attempt:**
If student already has an in-progress attempt, API returns status 200:
```json
{
  "attempt": { "attempt_id": 456, ... },
  "message": "Resuming existing attempt"
}
```

---

## 4. Loading Exam Questions

### Question Fetching (`lib/screens/exam_screen.dart` → `_loadExamQuestions()`)

**Process:**
```dart
1. Call: GET /api/exams/{examId}
2. API returns exam with sections and items
3. Extract exam duration (in minutes)
4. Parse questions with parseQuestionsForApp()
5. Initialize question UI (_initializeQuestions)
6. Shuffle questions and choices
7. Start timer with exam duration
```

**Key Code:**
```dart
final examData = await ApiService.fetchExamDetails(
  examId: int.parse(widget.examId),
);

// Extract duration
if (examData['exam']['duration'] != null) {
  examDurationSeconds = examData['exam']['duration'] * 60;
  _remainingSeconds = examDurationSeconds;
}

// Parse questions
final parsedQuestions = ApiService.parseQuestionsForApp(examData);
```

**API Endpoint:**
- `GET /api/exams/{examId}`
- Headers: `Authorization: Bearer {token}`
- Response:
```json
{
  "exam": {
    "exam_id": 9,
    "title": "Midterm Exam",
    "duration": 60,
    "sections": [
      {
        "section_id": 1,
        "title": "Part I",
        "directions": "Choose the best answer",
        "items": [
          {
            "item_id": 38,
            "item_type": "mcq",
            "question": "What is 2+2?",
            "stem": "What is 2+2?",
            "options": "{\"0\":\"3\",\"1\":\"4\",\"2\":\"5\"}",
            "points_awarded": 1,
            "order": 1
          }
        ]
      }
    ]
  }
}
```

**Question Type Conversion:**
```dart
API Type → App Type
---------   --------
mcq      → mcq
torf     → true_false
iden     → identification
enum     → enumeration
essay    → essay
```

**Options Parsing:**

The API returns options in different formats - all handled by the parser:

1. **JSON String (most common):**
   ```json
   "options": "{\"0\":\"yes\",\"1\":\"no\"}"
   ```
   Decoded to Map, then values extracted in sorted order

2. **Map/Object:**
   ```json
   "options": {"0": "yes", "1": "no"}
   ```
   Keys sorted numerically, values extracted

3. **Array:**
   ```json
   "options": ["yes", "no"]
   ```
   Used directly

**Parsed Question Structure:**
```dart
{
  'id': 'item_38',
  'itemId': 38,
  'sectionId': 1,
  'sectionTitle': 'Part I',
  'type': 'mcq',
  'question': 'What is 2+2?',
  'choices': ['3', '4', '5'],
  'marks': 1,
  'order': 1
}
```

---

## 5. Recording Answers

### Answer Storage (`lib/screens/exam_screen.dart`)

**Local Storage:**
Answers are stored in the `studentAnswers` map as the student progresses:

```dart
Map<String, dynamic> studentAnswers = {
  'item_38': '1',           // MCQ: option index
  'item_39': 'true',        // True/False
  'item_40': 'Paris',       // Identification
  'item_41': ['a', 'b'],    // Enumeration: array
  'item_42': 'Essay text'   // Essay
};
```

**Key Code - Saving Answer:**
```dart
// MCQ/True-False
setState(() {
  studentAnswers[questionId] = selectedOption;
});

// Identification/Essay
studentAnswers[questionId] = textController.text;

// Enumeration
studentAnswers[questionId] = answersArray;
```

**Local Persistence:**
Answers are saved to Hive whenever they change:
```dart
void saveLocalData() {
  if (attemptId == null) return;
  
  examBox.put(attemptId, {
    'attemptId': attemptId,
    'answers': studentAnswers,
    'remainingTime': _remainingSeconds,
    'submitted': false,
    'questions': questions,
  });
}
```

**Note:** The app does NOT sync answers to the server incrementally. All answers are sent only during final submission.

---

## 6. Timer Management

### Duration Tracking

**Timer Initialization:**
```dart
// Duration set from API response
examDurationSeconds = examData['exam']['duration'] * 60; // minutes → seconds
_remainingSeconds = examDurationSeconds;

// Start countdown
startTimer(); // Decrements _remainingSeconds every second
```

**Auto-Submit on Timeout:**
```dart
void startTimer() {
  _timer = Timer.periodic(Duration(seconds: 1), (timer) {
    if (_remainingSeconds <= 0) {
      _cancelTimer();
      if (!submitted) submitExam(autoSubmitted: true);
    } else {
      _remainingSeconds--;
    }
  });
}
```

**Duration Calculation for Submission:**
```dart
int durationTakenSeconds;

// Primary: Calculate from server's start_time
if (attemptStartTime != null) {
  final now = DateTime.now();
  durationTakenSeconds = now.difference(attemptStartTime).inSeconds;
} else {
  // Fallback: Calculate from timer
  durationTakenSeconds = (examDurationSeconds ?? 1800) - _remainingSeconds;
}
```

---

## 7. Submitting Exam

### Submission Process (`lib/screens/exam_screen.dart` → `submitExam()`)

**Process Flow:**
```dart
1. Check attemptId exists (created during start)
2. Calculate duration_taken in seconds
3. Format answers according to API spec
4. Call: POST /api/exam-attempts/{attemptId}/submit
5. API auto-grades and returns score
6. Save results locally
7. Show score to student
8. Navigate to dashboard or results
```

**Key Code:**
```dart
Future<void> submitExam({bool autoSubmitted = false}) async {
  // Calculate duration
  int durationTakenSeconds = 
    DateTime.now().difference(attemptStartTime).inSeconds;
  
  // Format answers for API
  final formattedAnswers = studentAnswers.entries.map((entry) {
    final question = questions.firstWhere((q) => q['id'] == entry.key);
    return {
      'item_id': question['itemId'],
      'answer': entry.value,
    };
  }).toList();
  
  // Submit to API
  final result = await ApiService.submitExamAttempt(
    attemptId: attemptId,
    durationTakenSeconds: durationTakenSeconds,
    answers: formattedAnswers,
  );
  
  // Extract score
  final score = result['attempt']['score'];
  
  // Show results
  showDialog(...);
}
```

**API Endpoint:**
- `POST /api/exam-attempts/{attemptId}/submit`
- Headers: `Authorization: Bearer {token}`
- Body:
```json
{
  "duration_taken": 3540,
  "answers": [
    {
      "item_id": 38,
      "answer": "1"
    },
    {
      "item_id": 39,
      "answer": "true"
    },
    {
      "item_id": 40,
      "answer": "Paris"
    },
    {
      "item_id": 41,
      "answer": ["apple", "banana"]
    }
  ]
}
```

**Response:**
```json
{
  "message": "Exam submitted successfully",
  "attempt": {
    "attempt_id": 456,
    "start_time": "2025-10-24T09:00:00Z",
    "end_time": "2025-10-24T09:59:00Z",
    "score": 85,
    "status": "submitted"
  }
}
```

**Answer Format by Question Type:**

| Question Type | Answer Format | Example |
|---------------|---------------|---------|
| MCQ | String (option index) | `"1"` |
| True/False | String | `"true"` or `"false"` |
| Identification | String | `"Paris"` |
| Enumeration | Array of strings | `["apple", "banana", "cherry"]` |
| Essay | String | `"This is my essay answer..."` |

---

## 8. Data Flow Summary

```
┌─────────────┐
│   Login     │
│   Screen    │
└──────┬──────┘
       │ POST /api/login
       │ → Receive token
       │ → Save to Hive
       ▼
┌─────────────┐
│  Dashboard  │
│   Screen    │
└──────┬──────┘
       │ Restore token from Hive
       │ GET /api/exams
       │ → List of exams
       │ → Cache in Hive
       │
       │ Student clicks "Take Exam"
       ▼
┌─────────────┐
│    Exam     │
│   Screen    │
└──────┬──────┘
       │
       │ 1. Start Attempt
       │    POST /api/exam-attempts
       │    → attempt_id, start_time
       │
       │ 2. Load Questions
       │    GET /api/exams/{id}
       │    → sections, items, duration
       │    → Parse questions
       │    → Start timer
       │
       │ 3. Student Answers
       │    → Store in studentAnswers map
       │    → Save to Hive (local only)
       │
       │ 4. Submit (Manual or Auto)
       │    POST /api/exam-attempts/{id}/submit
       │    → duration_taken, answers[]
       │    → Receive score
       │
       ▼
┌─────────────┐
│   Results   │
│   Dialog    │
└─────────────┘
```

---

## 9. Local Data Storage (Hive)

### Login Box (`loginBox`)
```dart
{
  'authToken': 'Bearer token...',
  'studentId': '12345',
  'password': '***',
  'rememberMe': true,
  'user': '{"first_name":"John",...}'
}
```

### Exam Box (`examBox`)

**Exam Metadata (cached from API):**
```dart
Key: 'meta_{examId}_{studentId}'
Value: {
  'id': '9',
  'examId': 9,
  'assignmentId': 123,
  'title': 'Midterm Exam',
  'available': true,
  'submitted': false,
  'recordType': 'exam',
  ...
}
```

**Attempt Data (in-progress):**
```dart
Key: attemptId (from server)
Value: {
  'attemptId': 456,
  'attemptStartTime': '2025-10-24T09:00:00Z',
  'answers': { 'item_38': '1', ... },
  'remainingTime': 2400,
  'submitted': false,
  'questions': [...],
  'recordType': 'attempt'
}
```

**Resume Reference:**
```dart
Key: '{examId}_{studentId}'
Value: {
  'attemptId': 456,
  'attemptStartTime': '2025-10-24T09:00:00Z',
  'submitted': false
}
```

---

## 10. Error Handling

### Common Issues and Solutions

**1. No Attempt ID**
```
Error: "Cannot submit - no attempt ID"
Cause: Attempt wasn't created successfully
Fix: Check auth token, network connection, assignment_id
```

**2. Authentication Failure**
```
Error: API returns 401 Unauthorized
Cause: Token not set or expired
Fix: Ensure token is saved during login and restored in dashboard
```

**3. Questions Not Loading**
```
Error: "FormatException" or "Type mismatch"
Cause: Options field has unexpected format
Fix: parseQuestionsForApp handles String/Map/List formats
```

**4. HiveError - Invalid Key**
```
Error: "Keys need to be Strings or integers"
Cause: Trying to use null attemptId as Hive key
Fix: saveLocalData() now checks if attemptId is null
```

---

## 11. Key Files Reference

### API Service
**File:** `lib/services/api_service.dart`

**Key Methods:**
- `login()` - POST /api/login
- `fetchExams()` - GET /api/exams
- `fetchExamDetails()` - GET /api/exams/{id}
- `startExamAttempt()` - POST /api/exam-attempts
- `submitExamAttempt()` - POST /api/exam-attempts/{id}/submit
- `parseExamForApp()` - Convert API exam to app format
- `parseQuestionsForApp()` - Parse sections/items to questions

### Screens
1. **LoginScreen** - `lib/screens/login_screen.dart`
   - Authenticates student
   - Saves auth token

2. **StudentDashboard** - `lib/screens/student_dashboard.dart`
   - Restores auth token
   - Fetches and displays exams
   - Navigates to exam screen

3. **ExamScreen** - `lib/screens/exam_screen.dart`
   - Starts exam attempt
   - Loads questions
   - Manages timer
   - Records answers
   - Submits to server

---

## 12. Testing Checklist

### Full Exam Flow Test
- [ ] Login with valid credentials
- [ ] Verify token is saved and restored
- [ ] Exam list loads from API
- [ ] Click "Take Exam" on available exam
- [ ] Exam attempt created on server (check Laravel logs)
- [ ] Questions load and display correctly
- [ ] Timer starts with correct duration
- [ ] Answer questions of different types
- [ ] Answers save locally
- [ ] Submit exam successfully
- [ ] Score displayed from server
- [ ] Exam marked as completed

### Edge Cases
- [ ] Resume in-progress exam after app restart
- [ ] Auto-submit when timer reaches zero
- [ ] Handle network errors gracefully
- [ ] Prevent double submission
- [ ] Handle expired/invalid token

---

**Last Updated:** October 24, 2025
**Version:** 1.0
**Related Documents:**
- `MOBILE_APP_API_REFERENCE.md` - Complete API specification
- `API_INTEGRATION_GUIDE.md` - API integration details
