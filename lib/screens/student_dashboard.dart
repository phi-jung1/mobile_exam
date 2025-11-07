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
  required Map exam, // ✅ Pass entire exam object for details
  int? attemptId,
}) {
  debugPrint('🔒 Navigating to OTP screen with exam details:');
  debugPrint('   Exam ID (numeric): $numericExamId');
  if (attemptId != null) {
    debugPrint('   Attempt ID: $attemptId');
  }
  debugPrint('   Student ID: $studentId (type: ${studentId.runtimeType})');
  
  // ✅ Extract exam details from the exam object
  final examTitle = exam['title']?.toString() ?? 'Untitled Exam';
  final examDate = exam['date']?.toString();
  final examDuration = exam['duration']?.toString();
  final questionCount = exam['questionCount'] as int?;
  
  // ✅ Parse time range if available (e.g., "10:00 AM - 12:00 PM")
  String? examTime;
  if (exam['startTime'] != null && exam['endTime'] != null) {
    examTime = '${exam['startTime']} - ${exam['endTime']}';
  } else if (exam['time'] != null) {
    examTime = exam['time'].toString();
  }
  
  debugPrint('   📋 Exam Title: $examTitle');
  debugPrint('   📅 Date: $examDate');
  debugPrint('   ⏰ Time: $examTime');
  debugPrint('   ⏱️ Duration: $examDuration');
  debugPrint('   📝 Questions: $questionCount');
  
  Navigator.pushNamed(context, '/otp', arguments: {
    'subject': subject,
    'forResults': forResults,
    'studentId': studentId,
    'examId': numericExamId.toString(),
    'attemptId': attemptId?.toString(),
    'examTitle': examTitle, // ✅ Pass exam title
    'examDate': examDate, // ✅ Pass date
    'examTime': examTime, // ✅ Pass time
    'duration': examDuration, // ✅ Pass duration
    'questionCount': questionCount, // ✅ Pass question count
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
            Icon(
              completed ? Icons.assignment_turned_in_outlined : Icons.assignment_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              completed ? "No completed exams yet" : "No available exams",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              completed 
                ? "Completed exams will appear here" 
                : "New exams will appear here when available",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: exams.length,
      itemBuilder: (context, index) {
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

        void onButtonPressed() {
          if (!isButtonEnabled) {
            if (!completed && !inSchedule) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: const Text(
                          "This exam is not yet available. Please wait for the scheduled time.",
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.orange.shade600,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
              debugPrint('📊 Found attempt ID in attempt object: $attemptIdForResults');
            } else if (exam['attemptId'] != null) {
              attemptIdForResults = exam['attemptId'] is int 
                  ? exam['attemptId'] 
                  : int.tryParse(exam['attemptId'].toString());
            }
            
            debugPrint('📊 Extracted attempt ID for results: $attemptIdForResults');
            
            if (attemptIdForResults == null) {
              debugPrint('⚠️ WARNING: No attempt ID found in exam data!');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("❌ Cannot view results: Missing attempt information"),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
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
            // ✅ Pass the entire exam object
            _navigateWithOtp(
              context: context,
              subject: subject,
              route: route,
              arguments: arguments,
              forResults: completed,
              examPassword: examPassword,
              numericExamId: numericExamId,
              exam: exam, // ✅ Pass entire exam object
              attemptId: attemptIdForResults,
            );
          } else {
            Navigator.pushNamed(context, route, arguments: arguments);
          }
        }
        // 🎨 Improved color scheme
        final cardColor = completed 
            ? (resultsReleased ? Colors.green.shade50 : Colors.orange.shade50)
            : (inSchedule ? Colors.blue.shade50 : Colors.grey.shade50);
            
        final accentColor = completed
            ? (resultsReleased ? Colors.green : Colors.orange)
            : (exam['available'] == true && inSchedule ? Colors.blue : Colors.grey);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 50)),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onButtonPressed,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accentColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        // 🎨 Header section with gradient
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor.withOpacity(0.1),
                                accentColor.withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // 🎨 Icon badge
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: accentColor.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      completed
                                          ? Icons.assignment_turned_in
                                          : Icons.assignment,
                                      color: accentColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          examTitle,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade900,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          subjectCode.isNotEmpty 
                                              ? '$subjectCode - $subject' 
                                              : subject,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: accentColor.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // 🎨 Body section
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Date row
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              
                              // Badges row
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (!completed && inSchedule)
                                    _modernBadge(
                                      "Available Now",
                                      Colors.green,
                                      Icons.check_circle,
                                    ),
                                  if (!completed && !inSchedule)
                                    _modernBadge(
                                      "Scheduled",
                                      Colors.blue,
                                      Icons.schedule,
                                    ),
                                  if (requiresOtp)
                                    _modernBadge(
                                      "Password Protected",
                                      Colors.purple,
                                      Icons.lock,
                                    ),
                                  if (completed)
                                    _modernBadge(
                                      resultsReleased ? "Graded" : "Under Review",
                                      resultsReleased ? Colors.green : Colors.orange,
                                      resultsReleased ? Icons.grade : Icons.pending,
                                    ),
                                  if (submitted)
                                    _modernBadge(
                                      exam['synced'] == true ? "Submitted" : "Submitting",
                                      exam['synced'] == true ? Colors.teal : Colors.orange,
                                      exam['synced'] == true ? Icons.cloud_done : Icons.cloud_upload,
                                    ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Action button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isButtonEnabled ? onButtonPressed : null,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor: accentColor,
                                    foregroundColor: Colors.white,
                                    elevation: isButtonEnabled ? 2 : 0,
                                    disabledBackgroundColor: Colors.grey.shade300,
                                    disabledForegroundColor: Colors.grey.shade600,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        completed
                                            ? Icons.assessment
                                            : Icons.play_arrow,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        buttonText,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
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
          ),
        );
      },
    );
  }

  Widget _modernBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color:  _darkenColor(color, 0.3),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _darkenColor(color, 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

Color _darkenColor(Color color, double amount) {
  assert(amount >= 0 && amount <= 1);
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}