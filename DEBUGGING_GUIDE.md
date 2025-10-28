# Debugging Guide: Why Exams Are Not Displaying

## Issues Found and Fixed

### 1. **API Response Parsing Issue** ✅ FIXED
**Problem:** The API returns a `status` field with values like "available", "completed", "scheduled", etc., but the parsing function was only checking for exact "available" status. This meant exams with status "in_progress" would not show up as available.

**Solution:** Updated `parseExamForApp()` in `api_service.dart` to properly convert the status string into boolean flags:
- `available` = true when status is "available" OR "in_progress"
- `submitted` = true when status is "completed"

### 2. **Missing Debug Logging** ✅ FIXED
**Problem:** No visibility into what data was being fetched, parsed, or filtered.

**Solution:** Added comprehensive debug logging throughout:
- API request/response logging
- Exam parsing logging
- Cache storage logging
- UI filtering logging

### 3. **Base URL Configuration** ✅ IMPROVED
**Problem:** Base URL was set to `http://127.0.0.1:8000/api` which doesn't work on:
- Android emulators (needs `10.0.2.2`)
- Physical devices (needs your computer's local IP)

**Solution:** Added detailed comments explaining how to configure the URL for different scenarios.

## How to Debug the Issue

### Step 1: Check the Debug Console

When you run the app, watch for these debug messages:

```
📡 Connecting to: http://127.0.0.1:8000/api/exams
📡 Response status: 200
✅ Fetched 3 exams
📋 Sample exam: {assignment_id: 1, exam_id: 7, title: Midterm Exam, ...}
📋 Parsing exam: Midterm Exam | Status: available | Completed: false | Available: true
💾 Caching exam: Midterm Exam | Available: true | Submitted: false
📦 Total exams in cache: 3
  - Midterm Exam: available=true, submitted=false, status=available
  - Final Exam: available=false, submitted=true, status=completed
✅ Available exams: 1
✅ Completed exams: 1
```

### Step 2: Common Error Messages

#### "Connection refused" or Timeout
```
⚠️ Error fetching exams: SocketException: Connection refused
   Base URL: http://127.0.0.1:8000/api
   Auth token present: true
```

**Fix:**
1. **On Android Emulator:** Change base URL to `http://10.0.2.2:8000/api`
2. **On Physical Device:** Change to `http://YOUR_COMPUTER_IP:8000/api` (e.g., `http://192.168.1.100:8000/api`)
3. **Make sure your Laravel server is running:** Run `php artisan serve` in your Laravel project

#### "401 Unauthorized"
```
❌ Failed to fetch exams: 401
   Response body: {"message":"Unauthenticated"}
```

**Fix:** The auth token is missing or invalid. Make sure you're logged in first.

#### "Empty exams array"
```
✅ Fetched 0 exams
⚠️ No exams returned from API, using cached data
```

**Fix:** The API is working but returning no exams. Check:
1. Is the student enrolled in any classes?
2. Are there exams assigned to those classes?
3. Run this SQL query in your database:
   ```sql
   SELECT * FROM exam_assignments WHERE student_id = YOUR_STUDENT_ID;
   ```

### Step 3: Test the API Directly

Use Postman or curl to test the API:

```bash
# 1. Login
curl -X POST http://localhost:8000/api/login \
  -H "Content-Type: application/json" \
  -d '{"login":"2021-12345","password":"password123","device_name":"test"}'

# Copy the token from the response

# 2. Get exams
curl -X GET http://localhost:8000/api/exams \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

Expected response:
```json
{
  "exams": [
    {
      "assignment_id": 1,
      "exam_id": 7,
      "title": "Midterm Examination",
      "status": "available",
      "subject": {
        "code": "MATH101",
        "name": "Mathematics"
      },
      ...
    }
  ]
}
```

### Step 4: Check Hive Cache

If exams were previously cached, you can check what's stored:

```dart
// Add this temporarily in your dashboard initState
debugPrint('=== ALL HIVE KEYS ===');
for (var key in examBox.keys) {
  debugPrint('Key: $key');
  final value = examBox.get(key);
  debugPrint('Value: $value');
}
```

### Step 5: Clear Cache and Retry

If old/bad data is cached, clear it:

```dart
// Add this button temporarily to your dashboard
ElevatedButton(
  onPressed: () async {
    await examBox.clear();
    debugPrint('Cache cleared!');
    setState(() {});
    _fetchExamsFromServer();
  },
  child: Text('Clear Cache & Reload'),
)
```

## Configuration Checklist

Before testing, ensure:

- [ ] Laravel server is running (`php artisan serve`)
- [ ] Base URL in `api_service.dart` is correct for your device
- [ ] Student account exists and is active
- [ ] Student is enrolled in at least one class
- [ ] At least one exam is assigned to that class
- [ ] Exam status is "available" (not "scheduled" or "expired")
- [ ] Auth token is being saved after login
- [ ] Internet/network connection is working

## Quick Fixes

### Fix 1: Update Base URL for Android Emulator

In `lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://10.0.2.2:8000/api';
```

### Fix 2: Update Base URL for Physical Device

1. Find your computer's IP address:
   - Windows: `ipconfig` (look for IPv4 Address)
   - Mac/Linux: `ifconfig` (look for inet)

2. Update base URL:
```dart
static const String baseUrl = 'http://192.168.1.100:8000/api';  // Use your IP
```

3. Make sure your Laravel server binds to all interfaces:
```bash
php artisan serve --host=0.0.0.0 --port=8000
```

### Fix 3: Temporarily Disable Token Requirement (Testing Only)

If you want to test without authentication, update the API routes in Laravel:

```php
// routes/api.php
Route::get('/exams', [ExamController::class, 'getExamsForStudent']);
// Remove ->middleware('auth:sanctum')
```

**⚠️ Don't forget to re-enable authentication in production!**

## Next Steps

1. **Run the app** and check the debug console
2. **Identify which error** you're seeing from the list above
3. **Apply the corresponding fix**
4. **Test again** after each fix

If exams still don't display after following this guide, check:
- Network connectivity between device and server
- CORS settings in Laravel (if using web browser)
- Firewall rules blocking connections
- Laravel logs: `storage/logs/laravel.log`

## Contact

If you're still stuck, provide:
1. Debug console output
2. API response from Postman/curl
3. Database query results
4. Your device type (emulator/physical, Android/iOS)
