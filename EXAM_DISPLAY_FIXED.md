# Exam Display Issue - FIXED

## Problem
The exam cards were displaying the **subject name** (e.g., "Mathematics") instead of the **exam title** (e.g., "Midterm Examination").

## Root Cause
In `student_dashboard.dart`, the exam card was displaying:
```dart
Text(
  subject,  // ❌ This shows "Mathematics", "English", etc.
  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
)
```

But the API provides both:
- `title`: "Midterm Examination" (the actual exam name)
- `subject.name`: "Mathematics" (the course subject)

## Solution Applied

### Updated Exam Card Display
Now showing BOTH the exam title and subject:

```dart
// Main heading - Exam Title
Text(
  examTitle,  // ✅ "Midterm Examination"
  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
)

// Subtitle - Subject with code
Text(
  '$subjectCode - $subject',  // ✅ "MATH101 - Mathematics"
  style: TextStyle(fontSize: 14, color: Colors.blue),
)
```

### Visual Example

**Before:**
```
┌─────────────────────────────┐
│ Mathematics                 │  ❌ Only subject name
│ Date: 2025-10-25 08:00:00  │
│ [Take Exam]                 │
└─────────────────────────────┘
```

**After:**
```
┌─────────────────────────────┐
│ Midterm Examination         │  ✅ Actual exam title
│ MATH101 - Mathematics       │  ✅ Subject with code
│ Date: 2025-10-25 08:00:00  │
│ [Take Exam]                 │
└─────────────────────────────┘
```

## API Data Structure

The API returns exams with this structure:
```json
{
  "assignment_id": 1,
  "exam_id": 7,
  "title": "Midterm Examination",        ← Exam name
  "description": "Covers chapters 1-5",
  "subject": {
    "id": 1,
    "code": "MATH101",                   ← Subject code
    "name": "Mathematics"                ← Subject name
  },
  "schedule_start": "2025-10-25 08:00:00",
  "status": "available"
}
```

## Parsed Data in App

The `parseExamForApp()` function extracts:
```dart
{
  'title': 'Midterm Examination',      // From apiExam['title']
  'subject': 'Mathematics',             // From apiExam['subject']['name']
  'subjectCode': 'MATH101',            // From apiExam['subject']['code']
  'examId': 7,
  'assignmentId': 1,
  // ... other fields
}
```

## Changes Made

### 1. Updated Variable Extraction
**File:** `lib/screens/student_dashboard.dart`

```dart
// Before
final subject = (exam['subject'] ?? 'Unknown Subject').toString();

// After - Added these variables
final examTitle = (exam['title'] ?? 'Untitled Exam').toString();
final subject = (exam['subject'] ?? 'Unknown Subject').toString();
final subjectCode = (exam['subjectCode'] ?? '').toString();
```

### 2. Updated Display Layout
**File:** `lib/screens/student_dashboard.dart`

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Exam title (main heading)
    Text(
      examTitle,  // ✅ NOW SHOWS: "Midterm Examination"
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
    SizedBox(height: 4),
    
    // Subject name with code
    Text(
      subjectCode.isNotEmpty ? '$subjectCode - $subject' : subject,
      style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
    ),
    // ... rest of the card
  ],
)
```

### 3. Added Debug Logging
Now logs what's being displayed:
```
📝 Displaying: "Midterm Examination" | Subject: Mathematics (MATH101) | Status: available
📝 Displaying: "Final Examination" | Subject: English (ENG101) | Status: completed
```

### 4. Updated Navigation Arguments
Now passes both exam title and subject to screens:
```dart
arguments: {
  'studentId': studentId,
  'subject': subject,          // "Mathematics"
  'examId': examId,
  'examTitle': examTitle,      // "Midterm Examination"
}
```

## Testing

Run the app and you should now see:
1. **Exam title** as the main heading (bold, larger text)
2. **Subject code and name** as subtitle (smaller, blue text)
3. Debug logs showing what's being displayed

Example debug output:
```
📊 Received 3 exams from API
📋 Parsing exam: Midterm Examination | Status: available | Completed: false | Available: true
💾 Caching exam: Midterm Examination | Available: true | Submitted: false
✅ Cached exam: Midterm Examination
📦 Total exams in cache: 3
  - Midterm Examination: available=true, submitted=false, status=available
  - Final Examination: available=false, submitted=true, status=completed
✅ Available exams: 1
✅ Completed exams: 1
📝 Displaying: "Midterm Examination" | Subject: Mathematics (MATH101) | Status: available
```

## Summary

✅ **Fixed**: Exam cards now display the actual exam title  
✅ **Added**: Subject information as a subtitle  
✅ **Enhanced**: Debug logging to track what's being displayed  
✅ **Improved**: Navigation passes complete exam information

The exam titles now match what the API provides!
