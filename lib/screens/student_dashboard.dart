import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class StudentDashboard extends StatefulWidget {
  final String studentId;
  final String? studentName;
  
  const StudentDashboard({
    super.key, 
    required this.studentId,
    this.studentName,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String _connectionStatus = "Checking connection...";
  Color _bannerColor = Colors.grey.shade300;
  late Box examBox;
  bool _isSyncing = false;
  bool _isManualSyncing = false;
  bool _disposed = false;
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  bool _showFAB = false;

  // Debouncing for connectivity changes
  Timer? _connectivityDebounceTimer;
  DateTime? _lastSyncTime;
  static const _syncCooldown = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initHive();
    _initConnectivity();

    // ✅ Fixed: Added disposal check and debouncing
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (_disposed) return;
      
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _updateConnectionStatus(result);
      
      // Debounce auto-sync to prevent rapid repeated calls
      _connectivityDebounceTimer?.cancel();
      _connectivityDebounceTimer = Timer(const Duration(seconds: 2), () {
        if (!_disposed && result != ConnectivityResult.none) {
          _autoSync();
        }
      });
    });

    _scrollController.addListener(() {
      if (!mounted || _disposed) return;
      setState(() => _showFAB = _scrollController.offset > 200);
    });
  }

  Future<void> _initHive() async {
    try {
      examBox = await Hive.openBox('examBox');
      
      // ✅ Restore authentication token from Hive
      try {
        final loginBox = await Hive.openBox('loginBox');
        final savedToken = loginBox.get('authToken');
        if (savedToken != null) {
          ApiService.setAuthToken(savedToken);
          debugPrint('✅ Restored auth token from storage');
        } else {
          debugPrint('⚠️ No auth token found in storage');
        }
      } catch (e) {
        debugPrint('⚠️ Error restoring auth token: $e');
      }

      // ✅ Ensure every existing record has a proper 'recordType'
      final keys = examBox.keys.toList();
      for (var key in keys) {
        if (_disposed) return;
        final record = examBox.get(key);
        if (record is Map && record['recordType'] == null) {
          await examBox.put(key, {...record, 'recordType': 'exam'});
        }
      }

      // 🧹 Clean malformed or old entries (safety measure)
      await _cleanupStaleData();

      // Fetch exams from server
      await _fetchExamsFromServer();

      if (mounted && !_disposed) {
        setState(() {}); // refresh UI
      }
    } catch (e) {
      debugPrint('⚠️ Error initializing Hive: $e');
    }
  }

  /// 🧹 Cleanup stale cached data (older than 7 days)
  Future<void> _cleanupStaleData() async {
    try {
      final now = DateTime.now();
      final keys = examBox.keys.toList();
      int deletedCount = 0;

      for (var key in keys) {
        if (_disposed) return;
        
        // Delete malformed keys
        if (key is! String || !key.contains('_')) {
          await examBox.delete(key);
          deletedCount++;
          continue;
        }

        // Delete old cached data (older than 7 days)
        final record = examBox.get(key);
        if (record is Map && record['timestamp'] != null) {
          try {
            final timestamp = DateTime.parse(record['timestamp']);
            if (now.difference(timestamp).inDays > 7) {
              await examBox.delete(key);
              deletedCount++;
            }
          } catch (e) {
            // Invalid timestamp, skip
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('🧹 Cleaned up $deletedCount stale cache entries');
      }
    } catch (e) {
      debugPrint('⚠️ Error during cleanup: $e');
    }
  }

  /// ✅ Fixed: Parallel fetch operations and consistent key format
  Future<void> _fetchExamsFromServer() async {
  if (_disposed) return;
  
  try {
    debugPrint('📡 Fetching exams from server...');
    
    // Fetch exams from API
    final apiExams = await ApiService.fetchExams();
    
    if (_disposed) return;
    
    debugPrint('📊 Received ${apiExams.length} exams from API');
    
    if (apiExams.isEmpty) {
      debugPrint('⚠️ No exams returned from API, using cached data');
      return;
    }

    debugPrint('✅ Processing ${apiExams.length} exams from server');

    // ✅ Fixed: Use Future.wait for parallel operations instead of sequential awaits
    final cacheOperations = <Future>[];
    
    for (var apiExam in apiExams) {
      if (_disposed) return;
      
      final exam = ApiService.parseExamForApp(apiExam);
      
      // ✅ CRITICAL FIX: Extract attempt ID from the API response
      int? attemptId;
      if (apiExam['attempt'] != null && apiExam['attempt'] is Map) {
        attemptId = apiExam['attempt']['attempt_id'];
        debugPrint('   Found attempt ID: $attemptId for exam ${exam['examId']}');
      }
      
      // ✅ Fixed: Consistent key format - always use widget.studentId
      final metaKey = 'meta_${exam['examId']}_${widget.studentId}';
      
      if (kDebugMode) {
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('💾 CACHING EXAM:');
        debugPrint('   Title: ${exam['title']}');
        debugPrint('   Exam ID: ${exam['examId']}');
        debugPrint('   Assignment ID: ${exam['assignmentId']}');
        debugPrint('   Attempt ID: $attemptId');  // ✅ Added
        debugPrint('   Cache Key: $metaKey');
        debugPrint('   Available: ${exam['available']}');
        debugPrint('   Submitted: ${exam['submitted']}');
      }
      
      final cachedData = {
        ...exam,
        'recordType': 'exam',
        'studentId': widget.studentId, // ✅ Always use widget.studentId
        'attemptId': attemptId,  // ✅ CRITICAL: Store attempt ID
        'attempt': apiExam['attempt'],  // ✅ Store full attempt object for reference
        'submitted': exam['submitted'],
        'available': exam['available'],
        'flagged': false,
        'completedAt': exam['attempt']?['end_time'],
        'questions': exam['questions'] ?? [],
        'timestamp': DateTime.now().toIso8601String(), // ✅ Add timestamp for cleanup

        'questionCount': exam['questions'] != null 
        ? (exam['questions'] as List).length 
        : (exam['questionCount'] ?? exam['question_count'] ?? 0),
      };
      
      // Add to parallel operations
      cacheOperations.add(examBox.put(metaKey, cachedData));
    }

    // ✅ Fixed: Execute all cache operations in parallel
    await Future.wait(cacheOperations);
    
    if (_disposed) return;

    if (mounted) {
      setState(() {}); // refresh UI
    }
    
    debugPrint('🔄 UI refreshed with ${apiExams.length} exams');
  } catch (e) {
    debugPrint('⚠️ Error fetching exams from server: $e');
    // Fallback to cached data (already in Hive)
  }
}

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (_disposed) return;
    
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    if (_disposed) return;
    
    setState(() {
      switch (result) {
        case ConnectivityResult.wifi:
          _connectionStatus = "Online via Wi-Fi: Exams synced automatically.";
          _bannerColor = Colors.green.shade100;
          break;
        case ConnectivityResult.mobile:
          _connectionStatus = "Online (Mobile Data): Sync may be slower.";
          _bannerColor = Colors.yellow.shade100;
          break;
        case ConnectivityResult.none:
          _connectionStatus = "Offline Mode: Showing cached exams.";
          _bannerColor = Colors.red.shade100;
          break;
        default:
          _connectionStatus = "Unknown network status.";
          _bannerColor = Colors.grey.shade300;
      }
    });
  }

  /// ✅ Fixed: Added cooldown period to prevent rapid syncs
  Future<void> _autoSync() async {
    if (_disposed || !mounted || _isSyncing) return;

    // Check cooldown period
    if (_lastSyncTime != null) {
      final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);
      if (timeSinceLastSync < _syncCooldown) {
        debugPrint('⏳ Sync cooldown active, skipping (${_syncCooldown.inSeconds - timeSinceLastSync.inSeconds}s remaining)');
        return;
      }
    }

    setState(() => _isSyncing = true);
    _lastSyncTime = DateTime.now();

    try {
      // Fetch fresh exams from server
      await _fetchExamsFromServer();

      if (!mounted || _disposed) return;
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("✅ Sync complete! Exams updated."),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Auto-sync error: $e');
      if (!mounted || _disposed) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("⚠️ Sync failed. Using cached data."),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted && !_disposed) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _autoSync();
    await Future.delayed(const Duration(milliseconds: 800));
  }

  Future<void> _logout() async {
    if (_disposed) return;
    
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (shouldLogout != true || _disposed) return;

    try {
      final loginBox = await Hive.openBox('loginBox');
      
      // ✅ FIX: Check Remember Me status BEFORE clearing data
      final rememberMe = loginBox.get('rememberMe', defaultValue: false);
      
      // Clear auth token and user data (always)
      await loginBox.delete('authToken');
      await loginBox.delete('user');
      
      // ✅ FIX: Only clear credentials if Remember Me is NOT enabled
      if (!rememberMe) {
        await loginBox.delete('studentId');
        await loginBox.delete('password');
        debugPrint('🗑️ Credentials cleared (Remember Me was off)');
      } else {
        debugPrint('💾 Credentials preserved (Remember Me is on)');
      }
      
      // Keep rememberMe flag as-is (don't change it)
      // await loginBox.put('rememberMe', false); // ❌ DON'T DO THIS
      
      // Clear auth token from ApiService
      ApiService.setAuthToken('');
      
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rememberMe 
                ? "✅ Logged out successfully! (Credentials saved)"
                : "✅ Logged out successfully!"
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Logout failed: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivityDebounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.studentName != oldWidget.studentName) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Fixed: Removed excessive debug logging in production
    if (kDebugMode) {
      debugPrint('\n🔍 BUILDING DASHBOARD - Reading from Hive cache...');
      debugPrint('   Student ID: ${widget.studentId}');
      debugPrint('   Total items in examBox: ${examBox.length}');
    }
    
    // ✅ Fixed: More defensive filtering with null safety
    final allExams = examBox.values
        .where((e) => 
          e is Map && 
          e['recordType'] == 'exam' && 
          e['studentId'] == widget.studentId)
        .cast<Map>()
        .toList();

    if (kDebugMode) {
      debugPrint('📦 Total exams in cache for student ${widget.studentId}: ${allExams.length}');
    }

    // ✅ Fixed: Defensive null checks for available and submitted fields
    final availableExams = allExams
        .where((e) => 
          (e['available'] == true) && 
          (e['submitted'] != true))
        .toList();

    if (kDebugMode) {
      debugPrint('✅ Available exams: ${availableExams.length}');
    }

    // ✅ Completed exams: only submitted
    final completedExams = allExams
        .where((e) => e['submitted'] == true)
        .toList();

    if (kDebugMode) {
      debugPrint('✅ Completed exams: ${completedExams.length}');
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: _buildAppBar(),
      floatingActionButton: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: _showFAB ? 1 : 0,
        child: _showFAB
            ? FloatingActionButton(
                onPressed: () {
                  _scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut);
                },
                backgroundColor: Colors.blueAccent,
                child: const Icon(Icons.arrow_upward),
              )
            : null,
      ),
      body: Column(
        children: [
          AnimatedConnectivityBanner(
            status: _connectionStatus,
            color: _bannerColor,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: TabBarView(
                controller: _tabController,
                children: [
                  ExamList(
                    exams: availableExams,
                    studentId: widget.studentId,
                    completed: false,
                    scrollController: _scrollController,
                  ),
                  ExamList(
                    exams: completedExams,
                    studentId: widget.studentId,
                    completed: true,
                    scrollController: _scrollController,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child: Text(
              (widget.studentName ?? widget.studentId).isNotEmpty 
                  ? (widget.studentName ?? widget.studentId)[0].toUpperCase()
                  : "S",
              style: const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Welcome, ${widget.studentName ?? widget.studentId}",
              style: const TextStyle(fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 3,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      actions: [
        if (_isManualSyncing)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Manual Sync',
            onPressed: () async {
              if (_disposed) return;
              
              setState(() => _isManualSyncing = true);
              final start = DateTime.now();

              try {
                await _autoSync();
                final duration = DateTime.now().difference(start);

                if (mounted && !_disposed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "✅ Sync complete in ${duration.inSeconds}s!",
                        style: const TextStyle(fontSize: 14),
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted && !_disposed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("❌ Sync failed: $e"),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } finally {
                if (mounted && !_disposed) {
                  setState(() => _isManualSyncing = false);
                }
              }
            },
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) async {
            if (value == 'logout') {
              await _logout();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text(
                    "Logout",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.white.withOpacity(0.3),
        ),
        tabs: const [
          Tab(text: "Available"),
          Tab(text: "Completed"),
        ],
      ),
    );
}

// ---------- Animated Connectivity Banner ----------
class AnimatedConnectivityBanner extends StatelessWidget {
  final String status;
  final Color color;
  const AnimatedConnectivityBanner({super.key, required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: color,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(
            status.startsWith("Offline") ? Icons.wifi_off : Icons.wifi,
            color: status.startsWith("Offline") ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(status, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class ExamList extends StatelessWidget {
  final List<Map> exams;
  final String studentId;
  final bool completed;
  final ScrollController scrollController;

  const ExamList({
    super.key,
    required this.exams,
    required this.studentId,
    required this.completed,
    required this.scrollController,
  });

  void _navigateWithOtp({
    required BuildContext context,
    required String subject,
    required String route,
    required Map arguments,
    required bool forResults,
    required String examPassword,
    required int numericExamId,
    required Map exam,
    int? attemptId,
  }) {
    debugPrint('🔒 Navigating to OTP screen with exam details:');
    debugPrint('   Exam ID (numeric): $numericExamId');
    if (attemptId != null) {
      debugPrint('   Attempt ID: $attemptId');
    }
    debugPrint('   Student ID: $studentId (type: ${studentId.runtimeType})');
    
    // ✅ Extract exam details
    final examTitle = exam['title']?.toString() ?? 'Untitled Exam';
    final examDate = exam['date']?.toString();
    final examDuration = exam['duration']?.toString();
    
    // ✅ FIXED: Try multiple possible field names for question count
    int? questionCount;
    if (exam['questionCount'] != null) {
      questionCount = exam['questionCount'] is int 
          ? exam['questionCount'] 
          : int.tryParse(exam['questionCount'].toString());
    } else if (exam['question_count'] != null) {
      questionCount = exam['question_count'] is int 
          ? exam['question_count'] 
          : int.tryParse(exam['question_count'].toString());
    } else if (exam['questions'] != null && exam['questions'] is List) {
      questionCount = (exam['questions'] as List).length;
    } else if (exam['total_questions'] != null) {
      questionCount = exam['total_questions'] is int 
          ? exam['total_questions'] 
          : int.tryParse(exam['total_questions'].toString());
    }
    
    // ✅ Parse time
    String? examTime;
    if (exam['startTime'] != null && exam['endTime'] != null) {
      examTime = '${exam['startTime']} - ${exam['endTime']}';
    } else if (exam['time'] != null) {
      examTime = exam['time'].toString();
    } else if (exam['start_time'] != null && exam['end_time'] != null) {
      examTime = '${exam['start_time']} - ${exam['end_time']}';
    }
    
    debugPrint('   📋 Exam Title: $examTitle');
    debugPrint('   📅 Date: $examDate');
    debugPrint('   ⏱️ Duration: $examDuration');
    debugPrint('   📝 Questions: $questionCount');
    
    Navigator.pushNamed(context, '/otp', arguments: {
      'subject': subject,
      'forResults': forResults,
      'studentId': studentId,
      'examId': numericExamId.toString(),
      'attemptId': attemptId?.toString(),
      'examTitle': examTitle,
      'examDate': examDate,
      'examTime': examTime,
      'duration': examDuration,
      'questionCount': questionCount,
      'onVerified': () => Navigator.pushNamed(context, route, arguments: arguments),
    });
  }

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                completed ? Icons.assignment_turned_in_outlined : Icons.assignment_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              completed ? "No completed exams yet" : "No available exams",
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              completed 
                ? "Completed exams will appear here" 
                : "New exams will appear here when available",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      itemCount: exams.length,
      itemBuilder: (context, index) => _buildExamCard(context, index),
    );
  }

  Widget _buildExamCard(BuildContext context, int index) {
  final exam = exams[index];
  final numericExamId = exam['examId'] ?? 0;
  final examTitle = (exam['title'] ?? 'Untitled Exam').toString();
  final subject = (exam['subject'] ?? 'Unknown Subject').toString();
  final subjectCode = (exam['subjectCode'] ?? '').toString();
  final date = (exam['date'] ?? 'No date set').toString();
  final requiresOtp = exam['requiresOtp'] ?? false;
  final examPassword = (exam['examPassword'] ?? '1234').toString();
  final resultsReleased = exam['resultsReleased'] ?? false;
  final submitted = exam['submitted'] ?? false;
  final inSchedule = exam['inSchedule'] ?? false;

  final buttonText = completed
      ? (resultsReleased ? "View Results" : "Pending Results")
      : (inSchedule ? "Take Exam" : "Scheduled");

  final isButtonEnabled = !completed
      ? (exam['available'] == true && !exam['submitted'] && inSchedule)
      : resultsReleased;

  // Modern color scheme
  final cardColor = completed 
      ? (resultsReleased ? Colors.white : Colors.white)
      : (inSchedule ? Colors.white : Colors.white);
      
  final accentColor = completed
      ? (resultsReleased ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
      : (exam['available'] == true && inSchedule ? const Color(0xFF3B82F6) : const Color(0xFF6B7280));

  void onButtonPressed() {
    if (!isButtonEnabled) {
      if (!completed && !inSchedule) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.schedule_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "This exam is not yet available.",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    final route = completed ? '/results' : '/exam';
    
    int? attemptIdForResults;
    if (completed) {
      if (exam['attempt'] != null && exam['attempt'] is Map) {
        attemptIdForResults = exam['attempt']['attempt_id'];
      } else if (exam['attemptId'] != null) {
        attemptIdForResults = exam['attemptId'] is int 
            ? exam['attemptId'] 
            : int.tryParse(exam['attemptId'].toString());
      }
      
      if (attemptIdForResults == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Cannot view results: Missing attempt information"),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }
    }
    
    final arguments = completed
        ? {
            'attemptId': attemptIdForResults?.toString() ?? '',
            'studentId': studentId,
            'examTitle': examTitle,
            'subject': subject,
          }
        : {
            'studentId': studentId,
            'subject': subject,
            'examId': numericExamId.toString(),
            'examTitle': examTitle,
            'assignmentId': exam['assignmentId']?.toString() ?? numericExamId.toString(),
          };

    if (requiresOtp) {
      _navigateWithOtp(
        context: context,
        subject: subject,
        route: route,
        arguments: arguments,
        forResults: completed,
        examPassword: examPassword,
        numericExamId: numericExamId,
        exam: exam,
        attemptId: attemptIdForResults,
      );
    } else {
      Navigator.pushNamed(context, route, arguments: arguments);
    }
  }

  // Parse the ISO date format
  String formattedDate = date;
  String? formattedTime;
  try {
    final parsedDate = DateTime.parse(date);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    formattedDate = '${months[parsedDate.month - 1]} ${parsedDate.day}, ${parsedDate.year}';
    
    // Extract time
    final hour = parsedDate.hour;
    final minute = parsedDate.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    formattedTime = '$displayHour:$minute $period';
  } catch (e) {
    // Keep original date if parsing fails
  }

  return Padding(
    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: scale,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isButtonEnabled ? onButtonPressed : null,
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Accent bar at the top
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with icon and title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              completed
                                  ? (resultsReleased ? Icons.check_circle_outline : Icons.pending_outlined)
                                  : Icons.description_outlined,
                              color: accentColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          
                          // Title and subject
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  examTitle,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade900,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subjectCode.isNotEmpty ? subjectCode : subject,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Date and time row
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (formattedTime != null) ...[
                            const SizedBox(width: 16),
                            Icon(
                              Icons.access_time_outlined,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Status badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!completed && inSchedule)
                            _buildBadge(
                              "Available",
                              const Color(0xFF10B981),
                              Icons.check_circle,
                            ),
                          if (!completed && !inSchedule)
                            _buildBadge(
                              "Scheduled",
                              const Color(0xFF6B7280),
                              Icons.schedule,
                            ),
                          if (requiresOtp)
                            _buildBadge(
                              "Protected",
                              const Color(0xFF8B5CF6),
                              Icons.lock_outline,
                            ),
                          if (completed)
                            _buildBadge(
                              resultsReleased ? "Graded" : "Under Review",
                              resultsReleased ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              resultsReleased ? Icons.grade_outlined : Icons.pending_outlined,
                            ),
                          if (submitted)
                            _buildBadge(
                              "Submitted",
                              const Color(0xFF14B8A6),
                              Icons.cloud_done_outlined,
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Action button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isButtonEnabled ? onButtonPressed : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isButtonEnabled ? accentColor : Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade500,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                completed
                                    ? Icons.assessment_outlined
                                    : Icons.play_arrow_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                buttonText,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}