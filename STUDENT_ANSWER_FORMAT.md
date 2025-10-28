# Student Questions and Answers Format Documentation

This document describes the exact format of questions received from the server and answers submitted by students in the mobile exam application.

---

## Table of Contents
1. [Quick Reference: Submission Format](#quick-reference-submission-format)
2. [Question Format from Server](#question-format-from-server)
3. [Answer Submission Format](#answer-submission-format)
4. [Question Type Mappings](#question-type-mappings)
5. [Choice/Option Format](#choiceoption-format)
6. [Complete API Flow Example](#complete-api-flow-example)

---

## Quick Reference: Submission Format

### What the Mobile App Sends to Server

**Endpoint:**
```
POST /api/exam-attempts/{attemptId}/submit
```

**Headers:**
```
Content-Type: application/json
Accept: application/json
Authorization: Bearer {token}
```

**Body:**
```json
{
  "duration_taken": 3245,
  "answers": [
    {
      "item_id": 45,
      "answer": "B"
    },
    {
      "item_id": 46,
      "answer": "A"
    },
    {
      "item_id": 47,
      "answer": "Photosynthesis"
    }
  ]
}
```

**Field Details:**
- `duration_taken`: Integer - Total seconds from exam start to submission
- `answers`: Array - Only answered questions are included
- `item_id`: Integer - Database ID of the question (**must match** server's item_id)
- `answer`: String - For MCQ/TORF: option key (A, B, C, D). For text questions: the typed answer

**Critical Points:**
- ✅ MCQ/TORF answers are **option keys** (A, B, C, D), NOT text or indexes
- ✅ All answers are strings, even option keys
- ✅ Unanswered questions are NOT included in the array
- ✅ Requires valid `attemptId` from exam start
- ✅ Student can only submit once per attempt

---

## Question Format from Server

### Endpoint
```
GET /api/exams/{examId}
```

### Expected Response Structure
```json
{
  "exam": {
    "exam_id": 123,
    "title": "Math Midterm Exam",
    "duration": 90,
    "duration_seconds": 5400,
    "total_points": 100,
    "sections": [
      {
        "section_id": 1,
        "title": "Multiple Choice",
        "directions": "Choose the best answer",
        "items": [
          {
            "item_id": 45,
            "item_type": "mcq",
            "question": "What is 2 + 2?",
            "options": {
              "A": "3",
              "B": "4",
              "C": "5",
              "D": "6"
            },
            "points_awarded": 2,
            "order": 1
          },
          {
            "item_id": 46,
            "item_type": "torf",
            "question": "The Earth is flat.",
            "options": {
              "A": "True",
              "B": "False"
            },
            "points_awarded": 1,
            "order": 2
          },
          {
            "item_id": 47,
            "item_type": "iden",
            "question": "What is the process by which plants make food?",
            "options": null,
            "points_awarded": 3,
            "order": 3
          },
          {
            "item_id": 48,
            "item_type": "enum",
            "question": "List three primary colors.",
            "options": null,
            "points_awarded": 3,
            "order": 4
          },
          {
            "item_id": 49,
            "item_type": "essay",
            "question": "Explain the theory of relativity.",
            "options": null,
            "points_awarded": 10,
            "order": 5
          }
        ]
      }
    ]
  }
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `item_id` | Integer | **Primary key** - Unique database ID for the question |
| `item_type` | String | Question type: `"mcq"`, `"torf"`, `"iden"`, `"enum"`, `"essay"` |
| `question` | String | The question text |
| `options` | Object/null | For MCQ/TORF: key-value pairs (A→"answer text"). For others: null |
| `points_awarded` | Integer/Float | Points this question is worth |
| `order` | Integer | Display order within section |

---

## Answer Submission Format

### Endpoint
```
POST /api/exam-attempts/{attemptId}/submit
```

### Request Headers
```json
{
  "Content-Type": "application/json",
  "Accept": "application/json",
  "Authorization": "Bearer {auth_token}"
}
```

### Request Body Structure
```json
{
  "duration_taken": 3245,
  "answers": [
    {
      "item_id": 45,
      "answer": "B"
    },
    {
      "item_id": 46,
      "answer": "B"
    },
    {
      "item_id": 47,
      "answer": "Photosynthesis"
    },
    {
      "item_id": 48,
      "answer": "Red, Blue, Yellow"
    },
    {
      "item_id": 49,
      "answer": "The theory of relativity states that..."
    }
  ]
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `duration_taken` | Integer | **Total seconds** student took to complete the exam |
| `answers` | Array | List of all answered questions |
| `answers[].item_id` | Integer | **Must match** the `item_id` from the question |
| `answers[].answer` | String | The student's answer (format varies by question type) |

---

## Question Type Mappings

The mobile app converts Laravel's question types to internal format:

| Laravel Type | Mobile App Type | Description |
|--------------|-----------------|-------------|
| `mcq` | `mcq` | Multiple Choice Question |
| `torf` | `true_false` | True or False |
| `iden` | `identification` | Identification/Fill-in-the-blank |
| `enum` | `enumeration` | Enumeration/List |
| `enum_ordered` | `enumeration` | Enumeration (order matters) |
| `enum_unordered` | `enumeration` | Enumeration (order doesn't matter) |
| `essay` | `essay` | Essay/Long answer |

### Conversion Code Location
```dart
// In lib/services/api_service.dart
static String convertItemType(String apiType) {
  switch (apiType.toLowerCase()) {
    case 'mcq': return 'mcq';
    case 'torf': return 'true_false';
    case 'iden': return 'identification';
    case 'enum': return 'enumeration';
    case 'enum_ordered': return 'enumeration';
    case 'enum_unordered': return 'enumeration';
    case 'essay': return 'essay';
    default: return apiType;
  }
}
```

---

## Choice/Option Format

### Server Sends (Options Object)

**Format 1: Letter-keyed map (Recommended)**
```json
{
  "options": {
    "A": "Paris",
    "B": "London",
    "C": "Berlin",
    "D": "Madrid"
  }
}
```

**Format 2: Number-keyed map**
```json
{
  "options": {
    "0": "Paris",
    "1": "London",
    "2": "Berlin",
    "3": "Madrid"
  }
}
```
*Note: Mobile app converts numeric keys to letters (0→A, 1→B, etc.)*

**Format 3: Array**
```json
{
  "options": ["Paris", "London", "Berlin", "Madrid"]
}
```
*Note: Mobile app auto-generates keys A, B, C, D...*

### Mobile App Internal Storage

The app converts all formats to a standardized structure:
```dart
[
  {"key": "A", "text": "Paris"},
  {"key": "B", "text": "London"},
  {"key": "C", "text": "Berlin"},
  {"key": "D", "text": "Madrid"}
]
```

### Shuffling Behavior

**Before shuffle:**
```
A. Paris
B. London
C. Berlin
D. Madrid
```

**After shuffle (example):**
```
D. Madrid
A. Paris
C. Berlin
B. London
```

**Important:** The app submits the **option key** (A, B, C, D), not the index or text.

---

## Answer Format by Question Type

### 1. Multiple Choice (MCQ)

**Server sends:**
```json
{
  "item_id": 45,
  "item_type": "mcq",
  "question": "What is the capital of France?",
  "options": {
    "A": "Paris",
    "B": "London",
    "C": "Berlin",
    "D": "Madrid"
  }
}
```

**Student sees (after shuffle):**
```
D. Madrid
A. Paris     ← Student selects this
C. Berlin
B. London
```

**App submits:**
```json
{
  "item_id": 45,
  "answer": "A"
}
```

**Server should:** Compare `"A"` against the correct answer key stored in database

---

### 2. True or False (TORF)

**Server sends:**
```json
{
  "item_id": 46,
  "item_type": "torf",
  "question": "The Earth is flat.",
  "options": {
    "A": "True",
    "B": "False"
  }
}
```

**Student sees:**
```
A. True
B. False     ← Student selects this
```

**App submits:**
```json
{
  "item_id": 46,
  "answer": "B"
}
```

**Server should:** Compare `"B"` against the correct answer key

---

### 3. Identification (IDEN)

**Server sends:**
```json
{
  "item_id": 47,
  "item_type": "iden",
  "question": "What is the process by which plants make food?",
  "options": null
}
```

**Student types:**
```
Photosynthesis
```

**App submits:**
```json
{
  "item_id": 47,
  "answer": "Photosynthesis"
}
```

**Server should:** Compare answer text (case-insensitive recommended)

---

### 4. Enumeration (ENUM)

**Server sends (Ordered):**
```json
{
  "item_id": 48,
  "item_type": "enum_ordered",
  "question": "List the steps of the scientific method in order.",
  "options": null
}
```

**Server sends (Unordered):**
```json
{
  "item_id": 49,
  "item_type": "enum_unordered",
  "question": "List three primary colors.",
  "options": null
}
```

**Student sees (Ordered):**
```
┌────────────────────────────────────────┐
│ [Enumeration (Order Matters)]          │
│                                         │
│ ⚠️ Order matters! List your answers    │
│    in the correct sequence.            │
│                                         │
│ List the steps of the scientific      │
│ method in order.                       │
│ ┌─────────────────────────────────┐   │
│ │ List answers separated by commas│   │
│ └─────────────────────────────────┘   │
└────────────────────────────────────────┘
```

**Student types (Ordered):**
```
Observation, Hypothesis, Experiment, Conclusion
```

**App submits (Ordered):**
```json
{
  "item_id": 48,
  "answer": "Observation, Hypothesis, Experiment, Conclusion"
}
```

**Server should (Ordered):** 
- Compare answers in exact order
- `"Hypothesis, Observation, Experiment, Conclusion"` → ❌ Wrong order

**Student types (Unordered):**
```
Blue, Red, Yellow
```

**App submits (Unordered):**
```json
{
  "item_id": 49,
  "answer": "Blue, Red, Yellow"
}
```

**Server should (Unordered):** 
- Parse and check all items are present regardless of order
- `"Yellow, Blue, Red"` → ✅ Correct (all items present)

---

### 5. Essay (ESSAY)

**Server sends:**
```json
{
  "item_id": 49,
  "item_type": "essay",
  "question": "Explain the theory of relativity.",
  "options": null
}
```

**Student types:**
```
The theory of relativity, developed by Albert Einstein, 
consists of two parts: special relativity and general 
relativity...
```

**App submits:**
```json
{
  "item_id": 49,
  "answer": "The theory of relativity, developed by Albert Einstein, consists of two parts: special relativity and general relativity..."
}
```

**Server should:** Store for manual grading or use AI grading

---

## Complete API Flow Example

### Step 1: Start Exam Attempt

**Request:**
```
POST /api/exam-attempts
Content-Type: application/json
Authorization: Bearer {token}

{
  "exam_id": 123,
  "student_id": 456
}
```

**Response:**
```json
{
  "message": "Exam attempt started",
  "attempt": {
    "attempt_id": 789,
    "exam_id": 123,
    "student_id": 456,
    "start_time": "2025-10-25T10:00:00Z",
    "status": "in_progress"
  }
}
```

### Step 2: Load Questions

**Request:**
```
GET /api/exams/123
Authorization: Bearer {token}
```

**Response:** *(See [Question Format from Server](#question-format-from-server))*

### Step 3: Student Answers Questions

Student interacts with mobile app:
- MCQ/TORF: Selects radio button → App stores option key (A, B, C, D)
- Identification/Enumeration/Essay: Types text → App stores text string

### Step 4: Submit Answers

**Request:**
```
POST /api/exam-attempts/789/submit
Content-Type: application/json
Authorization: Bearer {token}

{
  "duration_taken": 3245,
  "answers": [
    {"item_id": 45, "answer": "B"},
    {"item_id": 46, "answer": "B"},
    {"item_id": 47, "answer": "Photosynthesis"},
    {"item_id": 48, "answer": "Red, Blue, Yellow"},
    {"item_id": 49, "answer": "The theory of relativity..."}
  ]
}
```

**Response:**
```json
{
  "message": "Exam submitted successfully",
  "attempt": {
    "attempt_id": 789,
    "score": 85.5,
    "status": "submitted",
    "end_time": "2025-10-25T10:54:05Z"
  }
}
```

---

## Important Notes for Server Implementation

### 1. Option Key Storage
✅ **DO:** Store the correct answer as the option key
```json
{
  "item_id": 45,
  "correct_answer": "A",
  "options": {"A": "Paris", "B": "London", "C": "Berlin", "D": "Madrid"}
}
```

❌ **DON'T:** Store the correct answer as index or text
```json
{
  "correct_answer": 0,        // Wrong - will break after shuffling
  "correct_answer": "Paris"   // Wrong - requires text matching
}
```

### 2. Answer Validation

**For MCQ/TORF:**
```php
// Validate submitted answer matches correct key
if ($submittedAnswer === $question->correct_answer_key) {
    // Correct
}
```

**For Identification:**
```php
// Case-insensitive comparison recommended
if (strtolower(trim($submittedAnswer)) === strtolower($question->correct_answer)) {
    // Correct
}
```

**For Enumeration:**
```php
// Split and compare individual items
$submitted = array_map('trim', explode(',', $submittedAnswer));
$correct = $question->correct_answers; // Array of accepted answers
// Check if all submitted items are in correct answers
```

**For Essay:**
```php
// Manual grading or AI-based scoring
// Store for instructor review
```

### 3. Duration Validation

```php
// Ensure duration doesn't exceed exam time limit
$maxDuration = $exam->duration_seconds;
if ($submittedDuration > $maxDuration + 60) { // Allow 60s grace period
    // Possible time manipulation
}
```

### 4. Required Fields

**All questions must have:**
- `item_id` (integer, primary key)
- `item_type` (string: mcq, torf, iden, enum, essay)
- `question` (string, non-empty)
- `points_awarded` (number > 0)

**MCQ/TORF must have:**
- `options` (object with at least 2 key-value pairs)

**Other types should have:**
- `options` set to `null` or omitted

---

## Data Type Reference

| Field | Expected Type | Example | Notes |
|-------|---------------|---------|-------|
| `item_id` | Integer | `45` | Primary key, required |
| `exam_id` | Integer | `123` | Required |
| `student_id` | Integer | `456` | Required |
| `attempt_id` | Integer | `789` | Required for submission |
| `duration_taken` | Integer | `3245` | In seconds |
| `answer` | String | `"A"`, `"Text"` | Always string, never null |
| `options` | Object/null | `{"A": "text"}` | Object for MCQ/TORF, null for others |
| `points_awarded` | Number | `2`, `2.5` | Can be integer or float |
| `score` | Float | `85.5` | Calculated score |

---

## Validation Checklist

### Server-Side Validation (Laravel)

- [ ] All `item_id` values are valid and belong to the exam
- [ ] Each question has a correct answer defined
- [ ] MCQ/TORF options are stored as key-value pairs (not arrays)
- [ ] Correct answers are stored as keys (A, B, C, D), not text
- [ ] Duration validation allows reasonable grace period
- [ ] Answer format matches question type
- [ ] Student can only submit once per attempt
- [ ] Attempt belongs to the student making the submission

### Mobile App Validation (Flutter)

- [x] Questions parsed correctly from all option formats
- [x] Choices converted to key-value pairs
- [x] Shuffling preserves key-value relationships
- [x] Answers stored as option keys for MCQ/TORF
- [x] Duration calculated from attempt start time
- [x] Only answered questions included in submission
- [x] Attempt ID required before submission

---

## Troubleshooting

### Issue: Wrong answers marked as correct

**Cause:** Server storing correct answer as text instead of key  
**Solution:** Change `correct_answer` from `"Paris"` to `"A"`

### Issue: All MCQ answers marked wrong

**Cause:** Server comparing answer text instead of keys  
**Solution:** Compare submitted key against stored correct answer key

### Issue: Options appearing in different order

**Expected:** This is intentional - the mobile app shuffles choices  
**Solution:** Use option keys for grading, not order/index

### Issue: True/False questions always wrong

**Cause:** Server expecting "True"/"False" text, app sending "A"/"B"  
**Solution:** Store correct answer as key ("A" or "B"), not text

---

## Code Examples

### Laravel: Store Question with Options
```php
$question = ExamItem::create([
    'exam_id' => $examId,
    'item_type' => 'mcq',
    'question' => 'What is the capital of France?',
    'options' => json_encode([
        'A' => 'Paris',
        'B' => 'London',
        'C' => 'Berlin',
        'D' => 'Madrid'
    ]),
    'correct_answer' => 'A',  // Store KEY, not text
    'points_awarded' => 2
]);
```

### Laravel: Grade Submitted Answer
```php
$isCorrect = $submittedAnswer === $question->correct_answer;
$pointsEarned = $isCorrect ? $question->points_awarded : 0;
```

### Flutter: Parse Question Options
```dart
// Handled automatically by ApiService.parseQuestionsForApp()
// Converts all formats to: [{"key": "A", "text": "Paris"}, ...]
```

### Flutter: Submit Answer
```dart
// MCQ/TORF: Submit the key
studentAnswers[questionId] = "A";

// Text-based: Submit the text
studentAnswers[questionId] = "Photosynthesis";
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-25 | Initial documentation |

---

## Contact

For questions or issues with this format, refer to:
- Mobile App: `lib/services/api_service.dart` (parsing logic)
- Mobile App: `lib/screens/exam_screen.dart` (submission logic)
- Server API: Laravel exam submission endpoint documentation
