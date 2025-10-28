# ExamInEase API Integration Guide for Flutter App

## Overview
This guide provides the actual API endpoints and response formats for integrating the Flutter mobile exam app with the ExamInEase web-based exam creation system.

**Base URL:** `https://your-domain.com/api`

---

## Authentication

### 1. Login
Authenticate a student and receive an API token.

**Endpoint:** `POST /api/login`

**Request Body:**
```json
{
  "login": "2021-12345",
  "password": "student_password",
  "device_name": "mobile-app"
}
```

**Response (200 OK):**
```json
{
  "token": "1|eyJ0eXAiOiJKV1QiLCJhbGc...",
  "user": {
    "id": 123,
    "student_id": 123,
    "id_number": "2021-12345",
    "first_name": "John",
    "last_name": "Doe",
    "middle_name": "M",
    "email": "john@example.com",
    "status": "Enrolled"
  }
}
```

**Response (422 Unprocessable Entity):**
```json
{
  "message": "The provided credentials are incorrect.",
  "errors": {
    "login": ["The provided credentials are incorrect."]
  }
}
```

**Response (403 Forbidden):**
```json
{
  "message": "Your account is not active. Please contact administration."
}
```

---

### 2. Get Current User Info
Get authenticated user's profile information.

**Endpoint:** `GET /api/me`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "user": {
    "id": 123,
    "student_id": 123,
    "id_number": "2021-12345",
    "first_name": "John",
    "last_name": "Doe",
    "middle_name": "M",
    "email": "john@example.com",
    "status": "Enrolled"
  }
}
```

---

### 3. Logout
Revoke the current API token.

**Endpoint:** `POST /api/logout`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "message": "Logged out successfully"
}
```

---

## Health Check

### Check Server Status
Verify the server is running and accessible.

**Endpoint:** `GET /api/health`

**Response (200 OK):**
```json
{
  "status": "ok",
  "timestamp": "2025-10-25T12:00:00+00:00",
  "message": "Server is running"
}
```

---

## Student Classes

### Get Enrolled Classes
Get all classes the authenticated student is enrolled in.

**Endpoint:** `GET /api/classes`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "classes": [
    {
      "class_id": 1,
      "title": "Mathematics 101 - Section A",
      "year_level": "1st Year",
      "section": "A",
      "semester": "1st Semester",
      "school_year": "2024-2025",
      "subject": {
        "id": 1,
        "code": "MATH101",
        "name": "Mathematics"
      }
    }
  ]
}
```

---

## Exams

### 1. Get Available Exams
Get all exams assigned to the authenticated student.

**Endpoint:** `GET /api/exams`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "exams": [
    {
      "assignment_id": 1,
      "exam_id": 7,
      "title": "Midterm Examination",
      "description": "Covers chapters 1-5",
      "subject": {
        "id": 1,
        "code": "MATH101",
        "name": "Mathematics"
      },
      "class": {
        "id": 1,
        "title": "Mathematics 101 - Section A"
      },
      "schedule_start": "2025-10-25 08:00:00",
      "schedule_end": "2025-10-25 11:00:00",
      "duration": 60,
      "duration_seconds": 3600,
      "total_points": 100,
      "no_of_items": 50,
      "status": "available",
      "requiresOtp": true,
      "resultsReleased": false,
      "allowReview": false,
      "attempt": null
    },
    {
      "assignment_id": 2,
      "exam_id": 8,
      "title": "Final Examination",
      "description": "Comprehensive exam",
      "subject": {
        "id": 1,
        "code": "MATH101",
        "name": "Mathematics"
      },
      "class": {
        "id": 1,
        "title": "Mathematics 101 - Section A"
      },
      "schedule_start": "2025-11-15 08:00:00",
      "schedule_end": "2025-11-15 11:00:00",
      "duration": 120,
      "duration_seconds": 7200,
      "total_points": 150,
      "no_of_items": 75,
      "status": "completed",
      "requiresOtp": false,
      "resultsReleased": true,
      "allowReview": false,
      "attempt": {
        "attempt_id": 5,
        "start_time": "2025-11-15 08:05:00",
        "end_time": "2025-11-15 10:05:00",
        "score": 125,
        "status": "submitted"
      }
    }
  ]
}
```

**Status Values:**
- `available` - Exam is ready to be taken
- `scheduled` - Exam is scheduled for future date
- `expired` - Exam schedule has ended
- `completed` - Student has submitted the exam
- `in_progress` - Student has started but not submitted

---

### 2. Get Exam Details with Questions
Get detailed exam information including all questions and sections.

**Endpoint:** `GET /api/exams/{examId}`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "exam": {
    "exam_id": 7,
    "title": "Midterm Examination",
    "description": "Covers chapters 1-5",
    "subject": {
      "id": 1,
      "code": "MATH101",
      "name": "Mathematics"
    },
    "schedule_start": "2025-10-25 08:00:00",
    "schedule_end": "2025-10-25 11:00:00",
    "duration": 60,
    "duration_seconds": 3600,
    "total_points": 100,
    "no_of_items": 50,
    "requiresOtp": true,
    "sections": [
      {
        "section_id": 1,
        "title": "Multiple Choice",
        "directions": "Choose the best answer",
        "order": 1,
        "items": [
          {
            "item_id": 1,
            "question": "What is 2 + 2?",
            "item_type": "mcq",
            "options": ["3", "4", "5", "6"],
            "points_awarded": 2,
            "order": 1
          },
          {
            "item_id": 2,
            "question": "What is the capital of France?",
            "item_type": "mcq",
            "options": ["London", "Berlin", "Paris", "Madrid"],
            "points_awarded": 2,
            "order": 2
          }
        ]
      },
      {
        "section_id": 2,
        "title": "True or False",
        "directions": "Write T for true, F for false",
        "order": 2,
        "items": [
          {
            "item_id": 3,
            "question": "The earth is flat",
            "item_type": "torf",
            "options": ["True", "False"],
            "points_awarded": 1,
            "order": 1
          }
        ]
      },
      {
        "section_id": 3,
        "title": "Identification",
        "directions": "Write the correct answer",
        "order": 3,
        "items": [
          {
            "item_id": 4,
            "question": "Who invented the telephone?",
            "item_type": "iden",
            "options": null,
            "points_awarded": 3,
            "order": 1
          }
        ]
      },
      {
        "section_id": 4,
        "title": "Essay",
        "directions": "Answer in 3-5 sentences",
        "order": 4,
        "items": [
          {
            "item_id": 5,
            "question": "Explain the theory of relativity",
            "item_type": "essay",
            "options": null,
            "points_awarded": 10,
            "order": 1
          }
        ]
      }
    ]
  },
  "attempt": null
}
```

**Response (404 Not Found):**
```json
{
  "message": "Exam not found or not accessible"
}
```

**Item Types:**
- `mcq` - Multiple Choice Question
- `torf` - True or False
- `iden` - Identification
- `enum` - Enumeration
- `essay` - Essay Question

---

### 3. Verify Exam Password (OTP)
Verify the exam password before allowing access to the exam.

**Endpoint:** `POST /api/exams/{examId}/verify-otp`

**Headers:**
```
Authorization: Bearer {token}
```

**Request Body:**
```json
{
  "studentId": 123,
  "otp": "exam123"
}
```

**Response (200 OK - Password Correct):**
```json
{
  "verified": true,
  "message": "Password verified successfully"
}
```

**Response (200 OK - No Password Required):**
```json
{
  "verified": true,
  "message": "No password required for this exam"
}
```

**Response (400 Bad Request - Wrong Password):**
```json
{
  "verified": false,
  "message": "Invalid exam password"
}
```

**Response (404 Not Found):**
```json
{
  "verified": false,
  "message": "Exam not found"
}
```

---

### 4. Get Completed Exams
Get all exams the student has completed.

**Endpoint:** `GET /api/exams/completed`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "completed_exams": [
    {
      "attempt_id": 5,
      "exam_id": 8,
      "title": "Final Examination",
      "subject": {
        "id": 1,
        "code": "MATH101",
        "name": "Mathematics"
      },
      "score": 125,
      "total_points": 150,
      "percentage": 83.33,
      "completed_at": "2025-11-15 10:05:00",
      "submitted_at": "2025-11-15 10:05:00",
      "resultsReleased": true
    }
  ]
}
```

---

## Exam Attempts

### 1. Start Exam Attempt
Start a new exam attempt or resume an existing one.

**Endpoint:** `POST /api/exam-attempts`

**Headers:**
```
Authorization: Bearer {token}
```

**Request Body:**
```json
{
  "exam_assignment_id": 1
}
```

**Response (201 Created - New Attempt):**
```json
{
  "attempt": {
    "attempt_id": 10,
    "exam_assignment_id": 1,
    "student_id": 123,
    "start_time": "2025-10-25 08:05:00",
    "status": "in_progress"
  },
  "message": "Exam attempt started successfully"
}
```

**Response (200 OK - Resuming Existing Attempt):**
```json
{
  "attempt": {
    "attempt_id": 9,
    "exam_assignment_id": 1,
    "student_id": 123,
    "start_time": "2025-10-25 08:00:00",
    "status": "in_progress"
  },
  "message": "Resuming existing attempt"
}
```

**Response (400 Bad Request - Already Completed):**
```json
{
  "message": "You have already completed this exam"
}
```

**Response (400 Bad Request - Not Started Yet):**
```json
{
  "message": "Exam has not started yet"
}
```

**Response (400 Bad Request - Expired):**
```json
{
  "message": "Exam has ended"
}
```

**Response (403 Forbidden):**
```json
{
  "message": "You do not have access to this exam"
}
```

---

### 2. Submit Exam Attempt
Submit answers for an exam attempt.

**Endpoint:** `POST /api/exam-attempts/{attemptId}/submit`

**Headers:**
```
Authorization: Bearer {token}
```

**Request Body:**
```json
{
  "answers": [
    {
      "item_id": 1,
      "answer": "4"
    },
    {
      "item_id": 2,
      "answer": "Paris"
    },
    {
      "item_id": 3,
      "answer": "False"
    },
    {
      "item_id": 4,
      "answer": "Alexander Graham Bell"
    },
    {
      "item_id": 5,
      "answer": "The theory of relativity is Einstein's theory that describes how space and time are linked..."
    }
  ]
}
```

**Response (200 OK):**
```json
{
  "message": "Exam submitted successfully",
  "attempt": {
    "attempt_id": 10,
    "start_time": "2025-10-25 08:05:00",
    "end_time": "2025-10-25 09:30:00",
    "score": 85,
    "status": "submitted"
  }
}
```

**Response (404 Not Found):**
```json
{
  "message": "Exam attempt not found"
}
```

**Response (403 Forbidden):**
```json
{
  "message": "Unauthorized"
}
```

**Response (400 Bad Request):**
```json
{
  "message": "Exam already submitted"
}
```

**Auto-Grading Rules:**
- **MCQ & True/False:** Exact match with correct answer
- **Identification & Enumeration:** Case-insensitive comparison
- **Essay:** Not auto-graded (requires manual grading by instructor)

---

### 3. Get Exam Results
Get results for a completed exam attempt.

**Endpoint:** `GET /api/exam-attempts/{attemptId}/results`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "attempt": {
    "attempt_id": 10,
    "start_time": "2025-10-25 08:05:00",
    "end_time": "2025-10-25 09:30:00",
    "score": 85,
    "total_points": 100,
    "percentage": 85.00,
    "status": "submitted"
  },
  "exam": {
    "exam_id": 7,
    "title": "Midterm Examination",
    "subject": {
      "code": "MATH101",
      "name": "Mathematics"
    }
  }
}
```

**Response (404 Not Found):**
```json
{
  "message": "Exam attempt not found"
}
```

**Response (403 Forbidden):**
```json
{
  "message": "Unauthorized"
}
```

**Response (400 Bad Request):**
```json
{
  "message": "Exam not yet submitted"
}
```

---

## Error Responses

### Common HTTP Status Codes

- **200 OK** - Request successful
- **201 Created** - Resource created successfully
- **400 Bad Request** - Invalid request data
- **401 Unauthorized** - Missing or invalid authentication token
- **403 Forbidden** - Authenticated but not authorized for this action
- **404 Not Found** - Resource not found
- **422 Unprocessable Entity** - Validation failed
- **500 Internal Server Error** - Server error

### Error Response Format

```json
{
  "message": "Error description",
  "errors": {
    "field_name": ["Error message for this field"]
  }
}
```

---

## Authentication

All endpoints except `/api/login` and `/api/health` require authentication using Laravel Sanctum.

**Include the token in the Authorization header:**
```
Authorization: Bearer {token}
```

**Token Management:**
- Tokens are created on login
- Store the token securely in the Flutter app
- Include the token in all authenticated requests
- Revoke token on logout

---

## Implementation Steps for Flutter App

### 1. Update API Base URL
```dart
static const String baseUrl = 'https://your-actual-domain.com/api';
```

### 2. Store Token After Login
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('auth_token', response['token']);
```

### 3. Include Token in Requests
```dart
final token = await prefs.getString('auth_token');
final response = await http.get(
  Uri.parse('$baseUrl/exams'),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  },
);
```

### 4. Handle Exam Password Verification
```dart
// Before showing exam questions, verify password
final verified = await ApiService.verifyExamPassword(
  examId: examId,
  studentId: studentId,
  password: userInputPassword,
);

if (verified) {
  // Load exam questions
} else {
  // Show error message
}
```

### 5. Parse Exam Status
```dart
String getExamStatusText(String status) {
  switch (status) {
    case 'available':
      return 'Ready to Take';
    case 'scheduled':
      return 'Scheduled';
    case 'expired':
      return 'Ended';
    case 'completed':
      return 'Completed';
    case 'in_progress':
      return 'In Progress';
    default:
      return 'Unknown';
  }
}
```

---

## Testing the API

### Using Postman

1. **Test Login:**
   ```
   POST http://localhost/exam1/public/api/login
   Body: {"login": "2021-12345", "password": "password123"}
   ```

2. **Test Get Exams:**
   ```
   GET http://localhost/exam1/public/api/exams
   Headers: Authorization: Bearer {token}
   ```

3. **Test Health Check:**
   ```
   GET http://localhost/exam1/public/api/health
   ```

### Using cURL

```bash
# Login
curl -X POST http://localhost/exam1/public/api/login \
  -H "Content-Type: application/json" \
  -d '{"login":"2021-12345","password":"password123"}'

# Get exams (replace TOKEN with actual token)
curl -X GET http://localhost/exam1/public/api/exams \
  -H "Authorization: Bearer TOKEN"
```

---

## Security Considerations

1. **Always use HTTPS in production**
2. **Never expose exam passwords in logs**
3. **Validate student access to exams**
4. **Implement rate limiting** (Laravel Sanctum provides this)
5. **Sanitize user inputs** (Laravel does this automatically)
6. **Don't send correct answers** until exam is submitted

---

## Support & Troubleshooting

### Common Issues

**401 Unauthorized:**
- Check if token is included in headers
- Verify token hasn't expired
- Ensure user is logged in

**403 Forbidden:**
- User doesn't have access to this resource
- Student not enrolled in the class for this exam

**404 Not Found:**
- Check exam ID is correct
- Verify exam is assigned to student's class

**422 Validation Error:**
- Check request body matches required format
- Ensure all required fields are provided

---

## Changelog

**Version 1.0 - October 24, 2025**
- Initial API release
- Authentication endpoints
- Exam management endpoints
- Exam attempt endpoints
- Exam password verification
- Health check endpoint
- Completed exams endpoint

---

## Contact

For API issues or questions, contact the development team or submit an issue in the repository.
