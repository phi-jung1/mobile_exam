import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'student_dashboard.dart';


/// 🌟 Fade navigation helper
void navigateWithFade(BuildContext context, Widget destination) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 600),
    ),
    (route) => false,
  );
}

// ------------------------ EXAM SCREEN ------------------------

class ExamScreen extends StatefulWidget {
  final String studentId;
  final String subject;
  final String examId;
  final String? assignmentId; // Optional - falls back to examId

  const ExamScreen({
    super.key,
    required this.studentId,
    required this.subject,
    required this.examId,
    this.assignmentId,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> with WidgetsBindingObserver {
  late Box examBox;
   bool isExamInProgress = true;
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _questionScrollController = ScrollController();
  final Map<String, FocusNode> _focusNodes = {};

  // Questions will be loaded from API
  List<Map<String, dynamic>> questions = [];
  bool isLoadingQuestions = true;
  String? loadError;

  Map<String, dynamic> studentAnswers = {};
  Set<String> flaggedQuestions = {};
  bool showSummary = false;
  bool submitted = false;
  bool syncing = false;
  bool flaggedSuspicious = false;
  bool showSuspiciousBanner = false;
  bool _isWarningDialogVisible = false;
  bool _isExamPausedOverlayVisible = false;
  int _backgroundExitCount = 0;
  int _currentQuestionIndex = 0;
  int _lastHandledBackgroundCount = 0; 

  // Exam attempt tracking
  int? attemptId;
  DateTime? attemptStartTime;
  int? examAssignmentId;
  int? examDurationSeconds; // Will be set from API

  Timer? _timer;
  int _remainingSeconds = 0; // Will be set when exam duration is known

  @override
  void initState() {
    super.initState();

    _saveExamProgress();
    WidgetsBinding.instance.addObserver(this);
    examBox = Hive.box('examBox');
    _pageController = PageController(initialPage: _currentQuestionIndex);

    _secureExamEnvironment();
    
    // Load questions from API
    _loadExamQuestions();

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUnfinishedExam());
  }

  /// Load exam questions from API
  Future<void> _loadExamQuestions() async {
    try {
      debugPrint('📚 Loading questions for exam: ${widget.examId}');
      
      // TEMPORARILY SKIP CACHE - force fresh fetch from API
      debugPrint('⚠️ Skipping cache, forcing fresh API fetch...');
      
      // Try to load from cache first
      // final cachedQuestions = examBox.get('questions_${widget.examId}');
      // if (cachedQuestions != null && cachedQuestions is List) {
      //   setState(() {
      //     questions = List<Map<String, dynamic>>.from(cachedQuestions);
      //     isLoadingQuestions = false;
      //   });
      //   debugPrint('✅ Loaded ${questions.length} questions from cache');
      //   _initializeQuestions();
      //   return;
      // }

      debugPrint('🌐 Fetching from API...');
      debugPrint('   Exam ID: ${widget.examId}');
      
      // Fetch from API
      final examData = await ApiService.fetchExamDetails(
        examId: int.parse(widget.examId),
      );

      debugPrint('📦 Received exam data: ${examData != null ? "yes" : "no"}');
      if (examData != null) {
        debugPrint('   Keys: ${examData.keys.toList()}');
        if (examData['exam'] != null) {
          debugPrint('   Exam keys: ${examData['exam'].keys.toList()}');
        }
      }
      
      if (examData != null && examData['exam'] != null) {
        debugPrint('🔄 Parsing questions...');
        
        // Extract exam duration (in minutes from API, convert to seconds)
        final examInfo = examData['exam'];
        if (examInfo['duration'] != null) {
          examDurationSeconds = (examInfo['duration'] as num).toInt() * 60;
          _remainingSeconds = examDurationSeconds!;
          debugPrint('⏱️ Exam duration: ${examInfo['duration']} minutes ($examDurationSeconds seconds)');
        } else if (examInfo['duration_seconds'] != null) {
          examDurationSeconds = (examInfo['duration_seconds'] as num).toInt();
          _remainingSeconds = examDurationSeconds!;
          debugPrint('⏱️ Exam duration: $examDurationSeconds seconds');
        } else {
          // Fallback to 30 minutes if duration not provided
          examDurationSeconds = 60 * 30;
          _remainingSeconds = examDurationSeconds!;
          debugPrint('⚠️ No duration in exam data, using default: 30 minutes');
        }
        
        final parsedQuestions = ApiService.parseQuestionsForApp(examData);
        
        debugPrint('✅ Parsed ${parsedQuestions.length} questions');
        
        setState(() {
          questions = parsedQuestions;
          isLoadingQuestions = false;
        });

        // Cache questions
        await examBox.put('questions_${widget.examId}', questions);
        
        debugPrint('✅ Loaded ${questions.length} questions from API');
        _initializeQuestions();
      } else {
        setState(() {
          loadError = 'Failed to load exam questions - no data received';
          isLoadingQuestions = false;
        });
        debugPrint('❌ Failed to fetch exam details');
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ Error loading questions: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      setState(() {
        loadError = 'Error loading questions: ${e.toString()}';
        isLoadingQuestions = false;
      });
    }
  }

  /// Initialize questions after loading (shuffle, create focus nodes)
  void _initializeQuestions() {
    debugPrint('🔧 Initializing ${questions.length} questions');
    
    for (var q in questions) {
      // Debug log each question
      debugPrint('  Q[${q['id']}]: type=${q['type']}, choices=${q['choices']?.length ?? 0}, marks=${q['marks']}');
      
      // Shuffle MCQ choices (preserving key-value pairs)
      if (q['type'] == 'mcq' && q['choices'] != null) {
        q['choices'] = List<Map<String, String>>.from(q['choices'])..shuffle();
        debugPrint('    ✓ Shuffled ${q['choices'].length} choices');
      }
      
      // Initialize FocusNode for text fields
      if (q['type'] == 'identification' || q['type'] == 'enumeration' || q['type'] == 'essay') {
        _focusNodes[q['id']] = FocusNode();
        _focusNodes[q['id']]!.addListener(() {
          if (_focusNodes[q['id']]!.hasFocus) {
            _scrollToCurrentQuestion();
          }
        });
        debugPrint('    ✓ Created focus node for text input');
      }
    }
    
    // Shuffle questions
    questions.shuffle();
    debugPrint('✅ Questions initialized and shuffled');
  }

  Future<void> _secureExamEnvironment() async {
    try {
      await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
      await WakelockPlus.enable();
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (e) {
      debugPrint("Security setup failed: $e");
    }
  }
  

  // Auto-sync removed - API only supports final submission
  // void _startAutoSync() {
  //   _autoSyncTimer?.cancel();
  //   _autoSyncTimer = Timer.periodic(
  //     const Duration(seconds: autoSyncIntervalSeconds),
  //     (timer) async {
  //       if (!submitted && studentAnswers.isNotEmpty) {
  //         await _syncToServer();
  //       }
  //     },
  //   );
  // }

  

  // Legacy sync method - no longer used with new API
  Future<bool> _syncToServer() async {
  final attemptKey = 'attempt_${widget.examId}_${widget.studentId}';
  final metaKey = 'meta_${widget.examId}_${widget.studentId}';
  final now = DateTime.now().toIso8601String();

  // 🧾 Prepare payload to send to server
  final payload = {
    'studentId': widget.studentId,
    'examId': widget.examId,
    'answers': studentAnswers,
    'flaggedQuestions': flaggedQuestions.toList(),
    'submitted': true,
    'timestamp': now,
    'questions': questions,
  };

  final url = Uri.parse('https://yourserver.com/api/exam/submit');

  try {
    debugPrint('📡 Syncing exam ${widget.examId} for ${widget.studentId}...');
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      debugPrint('✅ Sync success for ${widget.examId}');

      // 🔹 Update attempt record
      final attempt = examBox.get(attemptKey) as Map? ?? {};
      await examBox.put(attemptKey, {
        ...attempt,
        'submitted': true,
        'synced': true,
        'flagged': flaggedSuspicious,
        'lastSyncedAt': now,
        'recordType': 'attempt',
      });

      // 🔹 Update meta record (used in dashboard)
      final meta = examBox.get(metaKey) as Map? ?? {};
      await examBox.put(metaKey, {
        ...meta,
        'submitted': true,
        'completed': true,
        'available': false,
        'synced': true,
        'recordType': 'exam',
        'lastSyncedAt': now,
      });

      return true;
    } else {
      debugPrint('❌ Sync failed: ${response.statusCode}');
      return false;
    }
  } catch (e) {
    debugPrint('⚠️ Sync error: $e');
    return false;
  }
}


  Future<void> markExamCompleted(
    String examId,
    Map<String, dynamic> answers, {
    int attemptId = 1,
  }) async {
    final examBox = Hive.box('examBox');
    final attemptKey = 'attempt_${examId}_${widget.studentId}_$attemptId';
    final metaKey = 'meta_${examId}_${widget.studentId}';
    final now = DateTime.now().toIso8601String();

    // ✅ Load attempt safely
    final rawAttempt = examBox.get(attemptKey);
    final attempt = (rawAttempt is Map)
        ? Map<String, dynamic>.from(rawAttempt)
        : <String, dynamic>{};

    // ✅ Update the attempt record
    await examBox.put(attemptKey, {
      ...attempt,
      'examId': examId,
      'studentId': widget.studentId,
      'attemptId': attemptId,
      'studentAnswers': answers,
      'submitted': true,
      'completed': true,
      'available': false,
      'completedAt': now,
      'recordType': 'attempt',
      'synced': attempt['synced'] ?? false,
    });

    // ✅ Update meta exam record (the one dashboard reads)
    final rawMeta = examBox.get(metaKey);
    final meta = (rawMeta is Map)
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};

    await examBox.put(metaKey, {
      ...meta,
      'id': examId,
      'examId': examId,
      'studentId': widget.studentId,
      'submitted': true,
      'completed': true,
      'available': false,
      'completedAt': now,
      'recordType': 'exam',
      'synced': true,
      // 🔹 Add missing data for result screen
      'questions': attempt['questions'] ?? [],
      'studentAnswers': attempt['studentAnswers'] ?? answers,
      'score': attempt['score'],
      'totalMarks': attempt['totalMarks'],
      'subject': attempt['subject'],
    });

    // ✅ Clean duplicate "exam" entries
    final duplicates = examBox.keys.where((key) {
      final record = examBox.get(key);
      return record is Map &&
          record['id'] == examId &&
          record['recordType'] == 'exam' &&
          key != metaKey;
    }).toList();

    for (var key in duplicates) {
      await examBox.delete(key);
    }

    debugPrint('✅ Cleaned ${duplicates.length} duplicate records for $examId');
    debugPrint('✅ Marked exam $examId as completed for ${widget.studentId}');

    // 🔹 Simulated sync (replace with actual upload logic if online)
    try {
      debugPrint('☁️ Synced completed exam $examId to server successfully.');
    } catch (e) {
      debugPrint('⚠️ Sync skipped (offline or failed): $e');
    }

    setState(() {}); // refresh UI
  }




  @override
  void dispose() {
    _cancelTimer();
    _pageController.dispose();
    _scrollController.dispose();
    _questionScrollController.dispose();
    for (var node in _focusNodes.values) node.dispose();
    saveLocalData();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scrollToCurrentQuestion() {
    // Scroll PageView content so the focused field is visible
      _questionScrollController.animateTo(
      _currentQuestionIndex * 300.0, // approximate offset per question card
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }
  
  void _cancelTimer() => _timer?.cancel();
  

  // Lifecycle changes
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (!mounted || submitted) return;

  switch (state) {
    case AppLifecycleState.paused:
    case AppLifecycleState.inactive:
      _handleExitAttempt();
      break;
    case AppLifecycleState.resumed:
      if (!submitted && (_timer == null || !(_timer?.isActive ?? false))) {
        startTimer();
      }
      _syncToServer();
      _checkExamStatus();
      break;
    default:
      break;
  }
}

// Back button pressed
Future<bool> _onWillPop() async {
  if (submitted) return true;

  _handleExitAttempt();

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Back navigation is disabled during the exam."),
      duration: Duration(seconds: 2),
    ),
  );

  return false;
}


// Update _handleExitAttempt
void _handleExitAttempt() {
  if (!mounted || submitted) return;

  flaggedSuspicious = true;
  showSuspiciousBanner = true;

  if (_backgroundExitCount == _lastHandledBackgroundCount) {
    _backgroundExitCount++;
    _lastHandledBackgroundCount = _backgroundExitCount;

    saveLocalData();
    _saveExamProgress();
    _cancelTimer();

    if (_backgroundExitCount >= 3) {
      submitExam(autoSubmitted: true);
      return;
    }

    if (!_isWarningDialogVisible) {
      _isExamPausedOverlayVisible = true; // show overlay

      String message;
      if (_backgroundExitCount == 1) {
        message = "You left the exam window. Please return immediately.";
      } else {
        message = "⚠️ You left the exam again. Leaving one more time will auto-submit your exam.";
      }
      _showWarningDialog(message);
    }
  }

  setState(() {});
}

// Update _showWarningDialog
void _showWarningDialog(String message) {
  if (!mounted) return;

  _isWarningDialogVisible = true;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      // Prevent dialog from being dismissed by back button
      onWillPop: () async => false,
      child: Stack(
        children: [
          // Frozen semi-transparent overlay
          if (_isExamPausedOverlayVisible)
            Opacity(
              opacity: 0.6,
              child: ModalBarrier(
                dismissible: false,
                color: Colors.black38,
              ),
            ),
          Center(
            child: AlertDialog(
              title: const Text("Exam Paused"),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!mounted) return;

                    Navigator.pop(context);
                    _isWarningDialogVisible = false;
                    _isExamPausedOverlayVisible = false; // hide overlay

                    if (!submitted) startTimer();
                  },
                  child: const Text("Continue Exam"),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
  /// Start exam attempt on the server
  Future<void> _startExamAttempt() async {
    try {
      debugPrint('🚀 Starting exam attempt for exam ${widget.examId}...');
      
      // Use assignmentId if provided, otherwise fall back to examId
      final assignmentIdStr = widget.assignmentId ?? widget.examId;
      final assignmentId = int.tryParse(assignmentIdStr);
      
      if (assignmentId == null) {
        debugPrint('❌ Invalid assignment ID: $assignmentIdStr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Invalid exam assignment ID')),
          );
        }
        return;
      }
      
      debugPrint('   Using assignment ID: $assignmentId');
      
      final result = await ApiService.startExamAttempt(
        examAssignmentId: assignmentId,
      );
      
      debugPrint('📥 API Response: $result');
      
      if (result == null) {
        debugPrint('❌ Failed to start attempt - no response');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start exam - no response from server')),
          );
        }
        return;
      }
      
      if (result['error'] != null) {
        debugPrint('❌ Error: ${result['error']}');
        // Show error to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${result['error']}')),
          );
        }
        return;
      }
      
      // Extract attempt data
      debugPrint('🔍 Checking for attempt data...');
      if (result['attempt'] != null) {
        debugPrint('   ✓ Found attempt object');
        attemptId = result['attempt']['attempt_id'];
        final startTimeStr = result['attempt']['start_time'];
        attemptStartTime = DateTime.parse(startTimeStr);
        
        debugPrint('✅ Attempt started:');
        debugPrint('   Attempt ID: $attemptId');
        debugPrint('   Start time: $attemptStartTime');
        debugPrint('   Message: ${result['message']}');
        
        // Save attempt info
        saveLocalData();
      } else {
        debugPrint('❌ No attempt object in response');
        debugPrint('   Response keys: ${result.keys.toList()}');
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ Error starting exam attempt: $e');
      debugPrint('   Stack: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting exam: $e')),
        );
      }
    }
  }

  void _checkForUnfinishedExam() async {
    String resumeKey = '${widget.examId}_${widget.studentId}';
    final savedRef = examBox.get(resumeKey);

    if (savedRef != null) {
      final savedAttemptId = savedRef['attemptId'];
      final savedSubmitted = savedRef['submitted'] is bool ? savedRef['submitted'] : false;

      if (!savedSubmitted && savedAttemptId != null) {
        attemptId = savedAttemptId;
        final savedStartTime = savedRef['attemptStartTime'];
        if (savedStartTime != null) {
          attemptStartTime = DateTime.parse(savedStartTime);
        }
        _showResumeDialog();
        return;
      }
    }

    // Start new attempt on server
    await _startExamAttempt();
    
    // Check if attempt was created successfully
    if (attemptId == null) {
      debugPrint('❌ Failed to create exam attempt - attempt ID is still null');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to start exam attempt. Please check your connection and try again.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context); // Go back to dashboard
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    _startExamNormally();
  }

  void _showResumeDialog() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Resume Exam"),
          content: const Text(
              "An unfinished exam was found. Would you like to resume your previous attempt or start fresh?"),
          actions: [
            TextButton(
              onPressed: () async {
                // Start fresh attempt
                if (!mounted) return;
                Navigator.pop(context);
                
                // Reset local data
                studentAnswers.clear();
                flaggedQuestions.clear();
                _remainingSeconds = examDurationSeconds ?? (60 * 30); // Fallback to 30 min
                submitted = false;
                flaggedSuspicious = false;

                // Start new attempt on server
                await _startExamAttempt();
                saveLocalData();
                _startExamNormally();
              },
              child: const Text("Start New"),
            ),
            ElevatedButton(
              onPressed: () {
                // Resume previous attempt safely
                if (!mounted) return;
                Navigator.pop(context);

                // Use stored attemptId to load correct answers and state
                loadLocalData();
                startTimer();
                // Auto-sync removed - only final submission supported
              },
            child: const Text("Resume"),
          ),
        ],
      ),
    );
  });
}


  void _startExamNormally() {
    loadLocalData();
    startTimer();
    // Auto-sync removed - only final submission supported
  }

  void loadLocalData() {
    final saved = examBox.get(attemptId);
    setState(() {
      studentAnswers = saved != null
          ? Map<String, dynamic>.from(saved['answers'] ?? {})
          : {};
      flaggedQuestions = saved != null
          ? Set<String>.from(saved['flaggedQuestions'] ?? [])
          : {};
      _remainingSeconds = saved != null
          ? (saved['remainingTime'] ?? examDurationSeconds).toInt()
          : examDurationSeconds;
      submitted = saved != null ? saved['submitted'] ?? false : false;
      flaggedSuspicious = saved != null ? saved['flagged'] ?? false : false;
    });

    // Always update resume reference to ensure next resume works
    examBox.put('${widget.examId}_${widget.studentId}', {
      'attemptId': attemptId,
      'submitted': submitted,
    });
  }


  void saveLocalData() {
    // Don't save if we don't have an attempt ID yet
    if (attemptId == null) {
      debugPrint('⚠️ Cannot save local data - no attempt ID yet');
      return;
    }
    
    examBox.put(attemptId, {
      'attemptId': attemptId,
      'attemptStartTime': attemptStartTime?.toIso8601String(),
      'recordType': 'attempt',
      'answers': studentAnswers,
      'flaggedQuestions': flaggedQuestions.toList(),
      'remainingTime': _remainingSeconds,
      'submitted': submitted,
      'synced': false,
      'flagged': flaggedSuspicious,
      'questions': questions,
    });

    // Save quick reference for resume check
    examBox.put('${widget.examId}_${widget.studentId}', {
      'attemptId': attemptId,
      'attemptStartTime': attemptStartTime?.toIso8601String(),
      'submitted': submitted,
    });
  }

  void startTimer() {
  _cancelTimer();
  _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
    // 1️⃣ Countdown logic
    if (_remainingSeconds <= 0) {
      _cancelTimer();
      if (!submitted) submitExam();
    } else {
      _remainingSeconds--;
    }

    // 2️⃣ Auto-save logic every 30 seconds
    if (_remainingSeconds % 30 == 0 && !submitted) {
      _saveExamProgress();
      saveLocalData();
    }

    setState(() {}); // refresh UI every second
  });
}


  String formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _saveExamProgress() async {
  // Example: save time left and current answers to Hive
  final box = await Hive.openBox('examProgress');
  box.put(widget.examId, {
    'answers': studentAnswers,
    'timeLeft': _remainingSeconds,
    'inProgress': true,
  });
}

  void _checkExamStatus() async {
    final box = await Hive.openBox('examProgress');
    final savedData = box.get(widget.examId);

    if (savedData != null && savedData['inProgress'] == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Resume Exam?'),
          content: const Text(
              'You had an unfinished exam. Would you like to continue where you left off?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resumeExam(savedData);
              },
              child: const Text('Resume'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                submitExam();
              },
              child: const Text('Submit Now'),
            ),
          ],
        ),
      );
    }
  }

  void _resumeExam(Map savedData) {
    setState(() {
      studentAnswers = Map<String, dynamic>.from(savedData['answers']);
      _remainingSeconds = savedData['timeLeft'];
    });
  }

  Future<void> _confirmSubmitExam(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Submit Exam?"),
        content: const Text(
            "Once submitted, you can no longer change your answers.\nDo you wish to continue?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Submit")),
        ],
      ),
    );
    if (confirm == true) submitExam();
  }

  Future<void> submitExam({bool autoSubmitted = false}) async {
    if (!mounted) return;
    
    // Check if we have attempt ID
    if (attemptId == null) {
      debugPrint('❌ Cannot submit - no attempt ID');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No active exam attempt')),
      );
      return;
    }
    
    setState(() => syncing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Calculate duration taken in seconds
      int durationTakenSeconds;
      if (attemptStartTime != null) {
        final now = DateTime.now();
        durationTakenSeconds = now.difference(attemptStartTime!).inSeconds;
      } else {
        // Fallback: use exam duration - remaining time
        durationTakenSeconds = (examDurationSeconds ?? (60 * 30)) - _remainingSeconds;
      }
      
      debugPrint('⏱️ Duration taken: $durationTakenSeconds seconds');

      // Format answers according to API spec
      final formattedAnswers = studentAnswers.entries.map((entry) {
        final questionId = entry.key;
        final answer = entry.value;
        
        // Find the original item_id from the question
        final question = questions.firstWhere(
          (q) => q['id'] == questionId,
          orElse: () => {},
        );
        
        final itemId = question['itemId'];
        final questionType = question['type'];
        
        if (itemId == null) {
          debugPrint('⚠️ No item_id found for question $questionId');
          return null;
        }
        
        // Format answer based on type
        String formattedAnswer;
        if (questionType == 'mcq' && answer is List) {
          // Multiple selections: join with commas
          formattedAnswer = answer.join(',');
          debugPrint('   MCQ answer: $formattedAnswer (${answer.length} selections)');
        } else {
          formattedAnswer = answer.toString();
        }
        
        return {
          'item_id': itemId,
          'answer': formattedAnswer,
        };
      }).where((a) => a != null).cast<Map<String, dynamic>>().toList();
      
      debugPrint('📤 Submitting ${formattedAnswers.length} answers...');

      // Submit to server
      final result = await ApiService.submitExamAttempt(
        attemptId: attemptId!,
        durationTakenSeconds: durationTakenSeconds,
        answers: formattedAnswers,
      );

      if (result == null || result['error'] != null) {
        final errorMsg = result?['error'] ?? 'Failed to submit exam';
        debugPrint('❌ Submission error: $errorMsg');
        
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Submission failed: $errorMsg')),
          );
        }
        
        setState(() => syncing = false);
        return;
      }

      // Extract score from response
      final attemptData = result['attempt'];
      final score = attemptData?['score'] ?? 0;
      
      debugPrint('✅ Exam submitted successfully - Score: $score');

      bool synced = true; // Already synced via API
      await markExamCompleted(widget.examId, studentAnswers);

      final attemptKey = 'attempt_${widget.examId}_${widget.studentId}';
      final metaKey = 'meta_${widget.examId}_${widget.studentId}';
      final existingMeta = examBox.get(metaKey) as Map? ?? {};

      await examBox.put(attemptKey, {
        'attemptId': attemptId,
        'examId': widget.examId,
        'studentId': widget.studentId,
        'subject': widget.subject,
        'answers': studentAnswers,
        'flaggedQuestions': flaggedQuestions.toList(),
        'submitted': true,
        'completed': true,
        'flagged': flaggedSuspicious,
        'synced': synced,
        'score': score,
        'completedAt': DateTime.now().toIso8601String(),
        'questions': questions,
        'recordType': 'attempt',
      });

      await examBox.put(metaKey, {
        ...existingMeta,
        'id': widget.examId,
        'studentId': widget.studentId,
        'subject': widget.subject,
        'submitted': true,
        'available': false,
        'completed': true,
        'allowReview': existingMeta['allowReview'] ?? false,
        'score': score,
        'studentAnswers': studentAnswers,
        'questions': questions,
        'resultsReleased': true,
        'synced': synced,
        'recordType': 'exam',
        'completedAt': DateTime.now().toIso8601String(),
      });

      setState(() {
        syncing = false;
        submitted = true;
      });

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (!mounted) return;

      final allowReview = (examBox.get(metaKey)?['allowReview'] ?? false) as bool;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(autoSubmitted ? "Exam Auto-Submitted" : "Exam Submitted"),
          content: Text(autoSubmitted
              ? "The exam was auto-submitted. Your score: $score"
              : "Your exam has been successfully submitted. Score: $score"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (allowReview) {
                  navigateWithFade(
                    context,
                    ReviewScreen(
                      duration: const Duration(minutes: 1),
                      studentAnswers: studentAnswers,
                      flaggedQuestions: flaggedQuestions,
                      questions: questions,
                      flagged: flaggedSuspicious,
                      studentId: widget.studentId,
                    ),
                  );
                } else {
              navigateWithFade(
                context,
                StudentDashboard(studentId: widget.studentId));
            }
          },
          child: const Text("OK"),
        ),
      ],
    ),
  );
    } catch (e, stackTrace) {
      debugPrint('⚠️ Exception during exam submission: $e');
      debugPrint('Stack: $stackTrace');
      
      setState(() => syncing = false);
      
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting exam: $e')),
        );
      }
    }
  }


  double getAnswerProgress() {
    if (questions.isEmpty) return 0.0;
    int answeredCount = studentAnswers.entries
        .where((entry) => questions.any(
            (q) => q['id'] == entry.key &&
                entry.value != null &&
                entry.value.toString().isNotEmpty))
        .length;
    return answeredCount / questions.length;
  }

  /// Get display info for question type
  Map<String, dynamic> getQuestionTypeInfo(String type, {String? originalType}) {
    // Check original type for enum variations
    if (originalType != null) {
      switch (originalType.toLowerCase()) {
        case 'enum_ordered':
          return {
            'label': 'Enumeration (Order Matters)',
            'color': Colors.deepOrange,
            'icon': Icons.format_list_numbered
          };
        case 'enum_unordered':
          return {
            'label': 'Enumeration (Any Order)',
            'color': Colors.orange,
            'icon': Icons.reorder
          };
      }
    }
    
    // Fallback to converted type
    switch (type.toLowerCase()) {
      case 'mcq':
        return {'label': 'Multiple Choice', 'color': Colors.blue, 'icon': Icons.list};
      case 'true_false':
        return {'label': 'True or False', 'color': Colors.purple, 'icon': Icons.check_circle_outline};
      case 'identification':
        return {'label': 'Identification', 'color': Colors.green, 'icon': Icons.edit};
      case 'enumeration':
        return {'label': 'Enumeration', 'color': Colors.orange, 'icon': Icons.format_list_numbered};
      case 'essay':
        return {'label': 'Essay', 'color': Colors.red, 'icon': Icons.article};
      default:
        return {'label': type.toUpperCase(), 'color': Colors.grey, 'icon': Icons.help_outline};
    }
  }

  Widget buildQuestion(Map<String, dynamic> q) {
  final isFlagged = flaggedQuestions.contains(q['id']);
  final typeInfo = getQuestionTypeInfo(q['type'] ?? 'unknown', originalType: q['originalType']);
  
  return Card(
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question type badge
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: typeInfo['color'].withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: typeInfo['color'], width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(typeInfo['icon'], size: 16, color: typeInfo['color']),
                const SizedBox(width: 6),
                Text(
                  typeInfo['label'],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: typeInfo['color'],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(q['question'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                icon: Icon(
                  isFlagged ? Icons.flag : Icons.outlined_flag,
                  color: isFlagged ? Colors.orange : Colors.grey,
                ),
                onPressed: submitted
                    ? null
                    : () {
                        setState(() {
                          if (isFlagged)
                            flaggedQuestions.remove(q['id']);
                          else
                            flaggedQuestions.add(q['id']);
                        });
                        saveLocalData();
                      },
              )
            ],
          ),
          const SizedBox(height: 12),
          if (q['type'] == 'mcq')
            if (q['choices'] != null && q['choices'] is List && q['choices'].isNotEmpty)
              ...q['choices'].map<Widget>((opt) {
                // opt is now a Map with 'key' and 'text'
                final optKey = opt['key'] ?? '';
                final optText = opt['text'] ?? '';
                
                // Get current selected answers as a list
                final selectedAnswers = studentAnswers[q['id']] is List 
                    ? List<String>.from(studentAnswers[q['id']])
                    : (studentAnswers[q['id']] != null && studentAnswers[q['id']].toString().isNotEmpty)
                        ? [studentAnswers[q['id']].toString()]
                        : <String>[];
                
                final isSelected = selectedAnswers.contains(optKey);
                
                return CheckboxListTile(
                  title: Text(optText),
                  value: isSelected,
                  onChanged: submitted
                      ? null
                      : (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              selectedAnswers.add(optKey);
                            } else {
                              selectedAnswers.remove(optKey);
                            }
                            studentAnswers[q['id']] = selectedAnswers.isEmpty ? null : selectedAnswers;
                          });
                          saveLocalData();
                          _saveExamProgress();
                        },
                  activeColor: Colors.blueAccent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList()
            else
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '⚠️ No answer choices available for this question',
                  style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                ),
              ),
          if (q['type'] == 'true_false')
            if (q['choices'] != null && q['choices'] is List && q['choices'].isNotEmpty)
              ...q['choices'].map<Widget>((opt) {
                final optKey = opt['key'] ?? '';
                final optText = opt['text'] ?? '';
                
                return RadioListTile<String>(
                  title: Text(optText),
                  value: optKey,
                  groupValue: studentAnswers[q['id']] as String?,
                  onChanged: submitted
                      ? null
                      : (String? value) {
                          setState(() {
                            studentAnswers[q['id']] = value;
                          });
                          saveLocalData();
                          _saveExamProgress();
                        },
                  activeColor: Colors.blueAccent,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList()
            else
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '⚠️ No answer choices available for this question',
                  style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                ),
              ),
          if (q['type'] == 'identification' ||
              q['type'] == 'enumeration' ||
              q['type'] == 'essay')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Add hint for ordered enumeration
                if (q['originalType']?.toLowerCase() == 'enum_ordered')
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.deepOrange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Order matters! List your answers in the correct sequence.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepOrange.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  focusNode: _focusNodes[q['id']],
                  initialValue: studentAnswers[q['id']],
                  enabled: !submitted,
                  maxLines: q['type'] == 'essay' ? null : 1,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: q['type'] == 'enumeration'
                        ? 'List answers separated by commas'
                        : 'Your answer...',
                  ),
                  onChanged: (val) {
                    studentAnswers[q['id']] = val;
                    saveLocalData();
                    _saveExamProgress();
                  },
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

  void _navigateToQuestion(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _currentQuestionIndex = index);

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    double screenWidth = MediaQuery.of(context).size.width;
    double itemWidth = 58;
    double targetScrollOffset =
        (index * itemWidth) - screenWidth / 2 + itemWidth / 2;

    if (targetScrollOffset < 0) targetScrollOffset = 0;
    _scrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }


  Widget buildQuestionNavigation() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final answer = studentAnswers[questions[index]['id']];
          final answered = answer != null && 
              ((answer is List && answer.isNotEmpty) || 
               (answer is! List && answer.toString().isNotEmpty));
          final flagged = flaggedQuestions.contains(questions[index]['id']);
          final isCurrent = _currentQuestionIndex == index;

          Color color = isCurrent
              ? Colors.blueAccent
              : answered
                  ? Colors.green
                  : flagged
                      ? Colors.orange
                      : Colors.grey[300]!;

          return GestureDetector(
            onTap: () => _navigateToQuestion(index),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

    Widget buildExamUI() {
      if (showSummary) {
        // Review mode remains mostly the same
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: questions.length,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final q = questions[index];
                  final answer = studentAnswers[q['id']];
                  final isFlagged = flaggedQuestions.contains(q['id']);
                  
                  // Handle multiple selections for MCQ
                  final selectedAnswers = answer is List 
                      ? List<String>.from(answer)
                      : (answer != null && answer.toString().isNotEmpty)
                          ? [answer.toString()]
                          : <String>[];
                  
                  return Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(q['question'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                              if (isFlagged)
                                const Icon(Icons.flag, color: Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (q['type'] == 'mcq')
                            if (q['choices'] != null && q['choices'] is List && q['choices'].isNotEmpty)
                              ...q['choices'].map((opt) {
                                final optKey = opt['key'] ?? '';
                                final optText = opt['text'] ?? '';
                                final isSelected = selectedAnswers.contains(optKey);
                                
                                return ListTile(
                                  title: Text(optText),
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: null,
                                  ),
                                  tileColor: isSelected ? Colors.green[100] : null,
                                );
                              }).toList()
                            else
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  '⚠️ No answer choices available',
                                  style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                                ),
                              ),
                          if (q['type'] == 'true_false')
                            if (q['choices'] != null && q['choices'] is List && q['choices'].isNotEmpty)
                              ...q['choices'].map((opt) {
                                final optKey = opt['key'] ?? '';
                                final optText = opt['text'] ?? '';
                                final isSelected = optKey == (answer?.toString() ?? '');
                                
                                return ListTile(
                                  title: Text(optText),
                                  leading: Radio(
                                    value: optKey,
                                    groupValue: answer?.toString(),
                                    onChanged: null,
                                  ),
                                  tileColor: isSelected ? Colors.green[100] : null,
                                );
                              }).toList()
                            else
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  '⚠️ No answer choices available',
                                  style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                                ),
                              ),
                          if (q['type'] == 'identification' ||
                              q['type'] == 'enumeration' ||
                              q['type'] == 'essay')
                            TextFormField(
                              initialValue: answer?.toString() ?? 'No answer',
                              enabled: false,
                              maxLines: q['type'] == 'essay' ? null : 1,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton(
                onPressed: () => setState(() => showSummary = false),
                child: const Text("Back to Exam"),
              ),
            )
          ],
        );
      }

      // ---------- Regular Exam Mode ----------
      return Column(
        children: [
          if (showSuspiciousBanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.redAccent,
              child: const Text(
                "⚠️ Suspicious activity detected! Leaving the exam may lead to automatic submission.",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: getAnswerProgress(),
                  backgroundColor: Colors.grey[300],
                  color: Colors.blueAccent,
                  minHeight: 8,
                ),
                const SizedBox(height: 4),
                Text(
                  "Progress: ${(getAnswerProgress() * 100).toStringAsFixed(0)}%",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          buildQuestionNavigation(),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: questions.length,
              onPageChanged: (index) => setState(() => _currentQuestionIndex = index),
              itemBuilder: (context, index) {
                return SingleChildScrollView(
                  controller: _questionScrollController,
                  padding: const EdgeInsets.all(12),
                  child: buildQuestion(questions[index]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _currentQuestionIndex > 0
                      ? () => _navigateToQuestion(_currentQuestionIndex - 1)
                      : null,
                  child: const Text("Previous"),
                ),
                ElevatedButton(
                  onPressed: _currentQuestionIndex < questions.length - 1
                      ? () => _navigateToQuestion(_currentQuestionIndex + 1)
                      : null,
                  child: const Text("Next"),
                ),
                ElevatedButton(
                  onPressed: submitted ? null : () => _confirmSubmitExam(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text("Submit Exam"),
                ),
              ],
            ),
          ),
        ],
      );
    }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while questions are being fetched
    if (isLoadingQuestions) {
      return Scaffold(
        appBar: AppBar(
          title: Text("${widget.subject} Exam"),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Loading exam questions...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // Show error if questions failed to load
    if (loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text("${widget.subject} Exam"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              Text('Failed to load exam', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              Text(loadError!, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isLoadingQuestions = true;
                    loadError = null;
                  });
                  _loadExamQuestions();
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Show empty state if no questions
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text("${widget.subject} Exam"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 20),
              const Text('No questions available', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text("${widget.subject} Exam"),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Time Left: ${formatTime(_remainingSeconds)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 60 ? Colors.red : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            body: syncing ? const SizedBox() : buildExamUI(),
          ),
          if (syncing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// ------------------------ REVIEW SCREEN ------------------------

class ReviewScreen extends StatefulWidget {
  final Duration duration;
  final Map<String, dynamic> studentAnswers;
  final Set<String> flaggedQuestions;
  final List<Map<String, dynamic>> questions;
  final bool flagged;
  final String studentId;

  const ReviewScreen({
    super.key,
    required this.duration,
    required this.studentAnswers,
    required this.flaggedQuestions,
    required this.questions,
    required this.flagged,
    required this.studentId,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late int remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    remainingSeconds = widget.duration.inSeconds;
    _startTimer();
  }

  void _startTimer() {
    _cancelTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds <= 0) _finishReview();
      else setState(() => remainingSeconds--);
    });
  }

  void _cancelTimer() => _timer?.cancel();

  Future<void> _finishReview() async {
  _cancelTimer();
  if (!mounted) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigateWithFade(
      context,
      StudentDashboard(studentId: widget.studentId),
    );
  });
}


  String formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Review Period")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              "You have ${formatTime(remainingSeconds)} to review your answers.",
              style: TextStyle(
                fontSize: 18,
                color: remainingSeconds <= 60 ? Colors.red : Colors.black,
              ),
            ),
          ),

          // ⚠️ Suspicious activity banner
          if (widget.flagged)
            Container(
              width: double.infinity,
              color: Colors.redAccent,
              padding: const EdgeInsets.all(8),
              child: const Text(
                "⚠️ Warning: App interruption detected during the exam. Your exam may have been auto-submitted if repeated.",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),

          Expanded(
            child: ListView(
              children: widget.questions.map((q) {
                final isFlagged = widget.flaggedQuestions.contains(q['id']);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(q['question'])),
                        if (isFlagged)
                          const Icon(Icons.flag, color: Colors.orange, size: 18),
                      ],
                    ),
                    subtitle: Text(
                        "Answer: ${widget.studentAnswers[q['id']] ?? 'No answer'}"),
                  ),
                );
              }).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              onPressed: _finishReview,
              child: const Text("Finish Review Now"),
            ),
          ),
        ],
      ),
    );
  }
}
