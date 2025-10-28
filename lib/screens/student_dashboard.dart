import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/api_service.dart';

class StudentDashboard extends StatefulWidget {
  final String studentId;
  final String? studentName;  // Add optional student name
  
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
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  bool _showFAB = false;

    @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initHive();
    _initConnectivity();

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _updateConnectionStatus(result);
      if (result != ConnectivityResult.none) _autoSync();
    });

    _scrollController.addListener(() {
      if (!mounted) return;
      setState(() => _showFAB = _scrollController.offset > 200);
    });
  }

  Future<void> _initHive() async {
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
    for (var key in examBox.keys) {
      final record = examBox.get(key);
      if (record is Map && record['recordType'] == null) {
        await examBox.put(key, {...record, 'recordType': 'exam'});
      }
    }

    // 🧹 Clean malformed or old entries (safety measure)
    for (var key in examBox.keys.toList()) {
      if (key is! String || !key.contains('_')) {
        await examBox.delete(key);
      }
    }

    // Fetch exams from server
    await _fetchExamsFromServer();

    setState(() {}); // refresh UI
  }

  /// Fetch exams from Laravel API
  Future<void> _fetchExamsFromServer() async {
    try {
      debugPrint('📡 Fetching exams from server...');
      
      // Fetch exams from API
      final apiExams = await ApiService.fetchExams();
      
      debugPrint('📊 Received ${apiExams.length} exams from API');
      
      if (apiExams.isEmpty) {
        debugPrint('⚠️ No exams returned from API, using cached data');
        return;
      }

      debugPrint('✅ Fetched ${apiExams.length} exams from server');

      // Parse and cache exams
      for (var apiExam in apiExams) {
        final exam = ApiService.parseExamForApp(apiExam);
        final metaKey = 'meta_${exam['examId']}_${widget.studentId}';
        
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('💾 CACHING EXAM:');
        debugPrint('   Title: ${exam['title']}');
        debugPrint('   Exam ID: ${exam['examId']}');
        debugPrint('   Assignment ID: ${exam['assignmentId']}');
        debugPrint('   Cache Key: $metaKey');
        debugPrint('   Available: ${exam['available']}');
        debugPrint('   Submitted: ${exam['submitted']}');
        debugPrint('   Exam Status: ${exam['examStatus']}');
        debugPrint('   Attempt Status: ${exam['attemptStatus']}');
        debugPrint('   In Progress: ${exam['inProgress']}');
        
        final cachedData = {
          ...exam,
          'recordType': 'exam',
          'studentId': widget.studentId,
          'attemptId': exam['attempt']?['attempt_id'],
          'submitted': exam['submitted'],
          'available': exam['available'],
          'flagged': false,
          'completedAt': exam['attempt']?['end_time'],
          'questions': exam['questions'] ?? [],
        };
        
        await examBox.put(metaKey, cachedData);

        debugPrint('✅ Cached successfully with key: $metaKey');
        debugPrint('════════════════════════════════════════════════════════════');
      }

      setState(() {}); // refresh UI
      
      debugPrint('🔄 UI refreshed with ${apiExams.length} exams');
    } catch (e) {
      debugPrint('⚠️ Error fetching exams from server: $e');
      // Fallback to cached data (already in Hive)
    }
  }


  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
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

  //autosync - fetch latest exams from server
  Future<void> _autoSync() async {
    if (!mounted || _isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      // Fetch fresh exams from server
      await _fetchExamsFromServer();

      if (!mounted) return;
      
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
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("⚠️ Sync failed. Using cached data."),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }



  Future<void> _handleRefresh() async {
    await _autoSync();
    await Future.delayed(const Duration(milliseconds: 800));
  }



  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('\n🔍 BUILDING DASHBOARD - Reading from Hive cache...');
    debugPrint('   Student ID: ${widget.studentId}');
    debugPrint('   Total items in examBox: ${examBox.length}');
    
    final allExams = examBox.values
    .where((e) => e is Map && e['recordType'] == 'exam' && e['studentId'] == widget.studentId)
    .cast<Map>()
    .toList();

    debugPrint('📦 Total exams in cache for student ${widget.studentId}: ${allExams.length}');
    for (var exam in allExams) {
      debugPrint('  ─────────────────────────────────────────────────────');
      debugPrint('  📋 ${exam['title']}');
      debugPrint('     Exam ID: ${exam['examId']}');
      debugPrint('     Assignment ID: ${exam['assignmentId']}');
      debugPrint('     Available: ${exam['available']}');
      debugPrint('     Submitted: ${exam['submitted']}');
      debugPrint('     Exam Status: ${exam['examStatus']}');
      debugPrint('     Attempt Status: ${exam['attemptStatus']}');
      debugPrint('     Record Type: ${exam['recordType']}');
      debugPrint('     Student ID in record: ${exam['studentId']}');
    }

    // ✅ Available exams: only not submitted AND exam is available
    final availableExams = allExams
        .where((e) => e['available'] == true && e['submitted'] == false)
        .toList();

    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('📊 EXAM FILTERING SUMMARY:');
    debugPrint('   Total exams in cache: ${allExams.length}');
    debugPrint('   Available exams: ${availableExams.length}');
    if (availableExams.isNotEmpty) {
      debugPrint('   Available exam titles:');
      for (var exam in availableExams) {
        debugPrint('      - ${exam['title']} (ID: ${exam['examId']})');
      }
    }
    debugPrint('════════════════════════════════════════════════════════════');

    // ✅ Completed exams: only submitted
    final completedExams = allExams
        .where((e) => e['submitted'] == true)
        .toList();

    debugPrint('✅ Completed exams: ${completedExams.length}');


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
                child: const Icon(Icons.arrow_upward),
              )
            : null,
      ),
      body: Column(
        children: [
          ConnectivityBanner(
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
      title: Text("Welcome, ${widget.studentName ?? widget.studentId}"),
      backgroundColor: Colors.transparent,
      elevation: 0,
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
              setState(() => _isManualSyncing = true);
              final start = DateTime.now();

              try {
                await _autoSync();
                final duration = DateTime.now().difference(start);

                if (mounted) {
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
                if (mounted) {
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
                if (mounted) setState(() => _isManualSyncing = false);
              }
            },
          ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(text: "Available"),
          Tab(text: "Completed"),
        ],
      ),
    );

}

// ---------- Modular Widgets ---------- //

class ConnectivityBanner extends StatelessWidget {
  final String status;
  final Color color;
  const ConnectivityBanner({super.key, required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      color: color,
      child: Row(
        children: [
          Icon(status.startsWith("Offline") ? Icons.wifi_off : Icons.wifi,
              color: status.startsWith("Offline") ? Colors.red : Colors.green),
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
    required String examPassword,  // Still accept but don't use - API will verify
    required int numericExamId,  // Add numeric exam ID parameter
  }) {
    debugPrint('🔒 Navigating to OTP screen:');
    debugPrint('   Exam ID (numeric): $numericExamId');
    debugPrint('   Student ID: $studentId (type: ${studentId.runtimeType})');
    
    Navigator.pushNamed(context, '/otp', arguments: {
      'subject': subject,
      'forResults': forResults,
      'studentId': studentId,
      'examId': numericExamId.toString(),  // Pass numeric exam ID as string
      'onVerified': () => Navigator.pushNamed(context, route, arguments: arguments),
    });
  }

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const Center(
        child: Text("No exams found.", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: exams.length,
      itemBuilder: (context, index) {
        final exam = exams[index];
        final numericExamId = exam['examId'] ?? 0;  // Numeric ID for API calls
        final examTitle = (exam['title'] ?? 'Untitled Exam').toString();
        final subject = (exam['subject'] ?? 'Unknown Subject').toString();
        final subjectCode = (exam['subjectCode'] ?? '').toString();
        final date = (exam['date'] ?? 'No date set').toString();
        final requiresOtp = exam['requiresOtp'] ?? false;
        final examPassword = (exam['examPassword'] ?? '1234').toString();  // Get password from exam data
        final resultsReleased = exam['resultsReleased'] ?? false;
        final submitted = exam['submitted'] ?? false;
        final inSchedule = exam['inSchedule'] ?? false;  // Check if in time window
        
        debugPrint('📝 Displaying: "$examTitle" | Subject: $subject ($subjectCode) | Status: ${exam['status']}');
        debugPrint('   Requires Password: $requiresOtp | Password from cache: "$examPassword"');

        final buttonText = completed
        ? (resultsReleased ? "View Results" : "Pending Results")
        : (inSchedule ? "Take Exam" : "Scheduled");

        // ✅ Button enabled only if:
        // - Taking exam: available && not submitted && in schedule
        // - Viewing results: resultsReleased
        final isButtonEnabled = !completed
            ? (exam['available'] == true && !exam['submitted'] && inSchedule)
            : resultsReleased;

        void onButtonPressed() {
          if (!isButtonEnabled) {
            // Show message if exam is not yet in schedule
            if (!completed && !inSchedule) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("⏰ This exam is not yet available. Please wait for the scheduled time."),
                  backgroundColor: Colors.orange.shade600,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          final route = completed ? '/results' : '/exam';
          final arguments = completed
              ? {
                  'examId': numericExamId.toString(),  // Use numeric ID for API
                  'studentId': studentId,
                  'examTitle': examTitle,
                  'subject': subject,
                }
              : {
                  'studentId': studentId,
                  'subject': subject,
                  'examId': numericExamId.toString(),  // Use numeric ID for API
                  'examTitle': examTitle,
                  'assignmentId': exam['assignmentId']?.toString() ?? numericExamId.toString(), // Pass assignment ID
                };

          if (requiresOtp) {
            debugPrint('🔒 Navigating to password verification with password: "$examPassword"');
            _navigateWithOtp(
              context: context,
              subject: subject,
              route: route,
              arguments: arguments,
              forResults: completed,
              examPassword: examPassword,  // Pass actual password from exam
              numericExamId: numericExamId,  // Pass numeric exam ID
            );
          } else {
            Navigator.pushNamed(context, route, arguments: arguments);
          }
        }


        // Determine card color
        final cardColor = completed
            ? Colors.orange.shade50
            : Colors.blue.shade50;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(2, 2)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onButtonPressed,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Exam title (main heading)
                    Text(
                      examTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    
                    // Subject name with code
                    Text(
                      subjectCode.isNotEmpty ? '$subjectCode - $subject' : subject,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Date and Status Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Date: $date",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        // ✅ Replace the Row below with a Wrap
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: [
                              // Show if exam is in schedule or upcoming
                              if (!completed && inSchedule)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    "📅 Active",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                              if (!completed && !inSchedule)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    "📋 Scheduled",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              if (requiresOtp)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    "🔒 Password",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ),
                              if (completed)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: resultsReleased
                                        ? Colors.green.shade100
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    resultsReleased ? "Results Ready" : "Pending",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: resultsReleased
                                          ? Colors.green.shade700
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              if (submitted)
                                  (exam['synced'] == true)
                                      ? Container(
                                          constraints: const BoxConstraints(maxWidth: 80),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            border: Border.all(color: Colors.green.shade200),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              "Synced ✅",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ),
                                        )
                                      : TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.6, end: 1.0),
                                          duration: const Duration(seconds: 1),
                                          curve: Curves.easeInOut,
                                          builder: (context, value, child) {
                                            return Opacity(
                                              opacity: value,
                                              child: Container(
                                                constraints: const BoxConstraints(maxWidth: 80),
                                                padding:
                                                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade50,
                                                  border: Border.all(color: Colors.orange.shade200),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    "Syncing…",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.orange,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        onEnd: () {
                                          if (context.mounted) {
                                            (context as Element).markNeedsBuild();
                                          }
                                        },
                                      ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isButtonEnabled ? onButtonPressed : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: completed ? Colors.orange : Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            buttonText,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
