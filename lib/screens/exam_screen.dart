import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
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
  // Method channels for anti-cheat
  static const _overlayChannel = MethodChannel('overlay_detector');
  static const _screenshotChannel = MethodChannel('screenshot_detector');
  static const _splitScreenChannel = MethodChannel('split_screen_detector');

  bool _disposed = false;
  late Box examBox;
  bool isExamInProgress = true;
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _questionScrollController = ScrollController();

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
  int _exitCount = 0;
  int _currentQuestionIndex = 0;

  // Exam attempt tracking
  int? attemptId;
  DateTime? attemptStartTime;
  int? examAssignmentId;
  int? examDurationSeconds;

  Timer? _timer;
  Timer? _autoSaveTimer;
  Timer? _autoSyncTimer;
  Timer? _overlayCheckTimer;
  Timer? _focusCheckTimer;
  int _remainingSeconds = 0;

  // Lifecycle flags
  bool _resumeDialogShown = false;
  DateTime? _lastExitEventTime;
  DateTime? _lastAutoSaveTime;

  //split screen detection method
  bool _isInSplitScreen = false;
  StreamSubscription? _splitScreenSubscription;
  bool _isSplitScreenWarningVisible = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    examBox = Hive.box('examBox');
    _pageController = PageController(initialPage: _currentQuestionIndex);

    // Wait for 3 frames before any dialog operations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (_disposed || !mounted) return;

        // Security setup
        await _secureExamEnvironment();

        if (_disposed || !mounted) return;

        // Load questions from API
        await _loadExamQuestions();

        if (_disposed || !mounted) return;

        // Check for unfinished exam (may show dialog)
        _checkForUnfinishedExam();

        // Start anti-cheat measures
        _listenForSplitScreen();
        _listenForScreenshots();
        _startFocusCheck();
        _startSplitScreenCheck();
        _startOverlayCheck();
      });
    });
  }

  /// Load exam questions from API
  Future<void> _loadExamQuestions() async {
    if (_disposed) return;

    try {
      if (kDebugMode) {
        debugPrint('📚 Loading questions for exam: ${widget.examId}');
      }

      // Fetch from API
      final examData = await ApiService.fetchExamDetails(
        examId: int.parse(widget.examId),
      );

      if (_disposed) return;

      if (kDebugMode) {
        debugPrint('📦 Received exam data: ${examData != null ? "yes" : "no"}');
      }

      if (examData != null && examData['exam'] != null) {
        if (kDebugMode) {
          debugPrint('🔄 Parsing questions...');
        }

        // Extract exam duration
        final examInfo = examData['exam'];
        if (examInfo['duration'] != null) {
          examDurationSeconds = (examInfo['duration'] as num).toInt() * 60;
          _remainingSeconds = examDurationSeconds!;
          if (kDebugMode) {
            debugPrint('⏱️ Exam duration: ${examInfo['duration']} minutes ($examDurationSeconds seconds)');
          }
        } else if (examInfo['duration_seconds'] != null) {
          examDurationSeconds = (examInfo['duration_seconds'] as num).toInt();
          _remainingSeconds = examDurationSeconds!;
          if (kDebugMode) {
            debugPrint('⏱️ Exam duration: $examDurationSeconds seconds');
          }
        } else {
          examDurationSeconds = 60 * 30; // 30 minutes default
          _remainingSeconds = examDurationSeconds!;
          if (kDebugMode) {
            debugPrint('⚠️ No duration in exam data, using default: 30 minutes');
          }
        }

        final parsedQuestions = ApiService.parseQuestionsForApp(examData);

        if (_disposed) return;

        if (kDebugMode) {
          debugPrint('✅ Parsed ${parsedQuestions.length} questions');
        }

        if (mounted) {
          setState(() {
            questions = parsedQuestions;
            isLoadingQuestions = false;
          });
        }

        // Cache questions asynchronously (non-blocking)
        examBox.put('questions_${widget.examId}', questions);

        if (kDebugMode) {
          debugPrint('✅ Loaded ${questions.length} questions from API');
        }
        _initializeQuestions();
      } else {
        if (_disposed) return;
        
        if (mounted) {
          setState(() {
            loadError = 'Failed to load exam questions - no data received';
            isLoadingQuestions = false;
          });
        }
        if (kDebugMode) {
          debugPrint('❌ Failed to fetch exam details');
        }
      }
    } catch (e, stackTrace) {
      if (_disposed) return;
      
      if (kDebugMode) {
        debugPrint('⚠️ Error loading questions: $e');
        debugPrint('📍 Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          loadError = 'Error loading questions: ${e.toString()}';
          isLoadingQuestions = false;
        });
      }
    }
  }

  /// Initialize questions after loading (shuffle choices, create focus nodes)
  void _initializeQuestions() {
    if (_disposed) return;

    if (kDebugMode) {
      debugPrint('🔧 Initializing ${questions.length} questions');
    }

    for (var q in questions) {
      if (kDebugMode) {
        debugPrint('  Q[${q['id']}]: type=${q['type']}, choices=${q['choices']?.length ?? 0}, marks=${q['marks']}');
      }

      // Shuffle MCQ choices (entire key-value pairs together)
      if (q['type'] == 'mcq' && q['choices'] != null) {
        q['choices'] = List<Map<String, String>>.from(q['choices'])..shuffle();
        if (kDebugMode) {
          debugPrint('    ✓ Shuffled ${q['choices'].length} choices');
        }
      }
    }

    // Shuffle the order of questions (optional, can disable if not desired)
    questions.shuffle();

    if (kDebugMode) {
      debugPrint('✅ Questions initialized and shuffled');
    }
  }


  Future<void> _secureExamEnvironment() async {
    if (_disposed) return;
    
    try {
      await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
      await WakelockPlus.enable();
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Security setup failed: $e");
      }
    }
  }

  /// Start exam attempt on the server
  Future<void> _startExamAttempt() async {
    if (_disposed) return;
    
    try {
      if (kDebugMode) {
        debugPrint('🚀 Starting exam attempt for exam ${widget.examId}...');
      }

      final assignmentIdStr = widget.assignmentId ?? widget.examId;
      final assignmentId = int.tryParse(assignmentIdStr);

      if (assignmentId == null) {
        if (kDebugMode) {
          debugPrint('❌ Invalid assignment ID: $assignmentIdStr');
        }
        if (_disposed || !mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Invalid exam assignment ID')),
        );
        return;
      }

      if (kDebugMode) {
        debugPrint('   Using assignment ID: $assignmentId');
      }

      final result = await ApiService.startExamAttempt(
        examAssignmentId: assignmentId,
      );

      if (_disposed) return;

      if (kDebugMode) {
        debugPrint('📥 API Response: $result');
      }

      if (result == null) {
        if (kDebugMode) {
          debugPrint('❌ Failed to start attempt - no response');
        }
        if (_disposed || !mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start exam - no response from server')),
        );
        return;
      }

      if (result['error'] != null) {
        if (kDebugMode) {
          debugPrint('❌ Error: ${result['error']}');
        }
        if (_disposed || !mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${result['error']}')),
        );
        return;
      }

      // Extract attempt data
      if (kDebugMode) {
        debugPrint('🔍 Checking for attempt data...');
      }
      if (result['attempt'] != null) {
        if (kDebugMode) {
          debugPrint('   ✓ Found attempt object');
        }
        attemptId = result['attempt']['attempt_id'];
        final startTimeStr = result['attempt']['start_time'];
        attemptStartTime = DateTime.parse(startTimeStr);

        if (kDebugMode) {
          debugPrint('✅ Attempt started:');
          debugPrint('   Attempt ID: $attemptId');
          debugPrint('   Start time: $attemptStartTime');
        }

        // Save attempt info
        _saveLocalDataThrottled();
      } else {
        if (kDebugMode) {
          debugPrint('❌ No attempt object in response');
        }
      }
    } catch (e, stackTrace) {
      if (_disposed) return;
      
      if (kDebugMode) {
        debugPrint('⚠️ Error starting exam attempt: $e');
        debugPrint('   Stack: $stackTrace');
      }
      if (_disposed || !mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting exam: $e')),
      );
    }
  }

  void _checkForUnfinishedExam() async {
    if (_disposed || _resumeDialogShown || !mounted) return;

    String resumeKey = '${widget.examId}_${widget.studentId}';
    final savedRef = examBox.get(resumeKey);

    if (savedRef != null) {
      final savedAttemptId = savedRef['attemptId'];
      final savedSubmitted = savedRef['submitted'] is bool ? savedRef['submitted'] : false;

      if (!savedSubmitted && savedAttemptId != null) {
        _resumeDialogShown = true;
        attemptId = savedAttemptId;
        final savedStartTime = savedRef['attemptStartTime'];
        if (savedStartTime != null) {
          attemptStartTime = DateTime.parse(savedStartTime);
        }
        
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_disposed || !mounted) return;
          _showResumeDialog();
        });
        return;
      }
    }

    // Start new attempt on server
    await _startExamAttempt();

    if (_disposed) return;

    // Check if attempt was created successfully
    if (attemptId == null) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create exam attempt - attempt ID is still null');
      }
      if (_disposed || !mounted) return;
      
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Failed to start exam attempt. Please check your connection and try again.'),
          actions: [
            TextButton(
              onPressed: () {
                if (!mounted) return;
                Navigator.pop(context);
                Navigator.pop(context); // Go back to dashboard
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    _startExamNormally();
  }

  void _showResumeDialog() {
    if (_disposed || !mounted) return;
    
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
              if (!mounted) return;
              Navigator.pop(context);

              // Reset local data
              studentAnswers.clear();
              flaggedQuestions.clear();
              _remainingSeconds = examDurationSeconds ?? (60 * 30);
              submitted = false;
              flaggedSuspicious = false;

              // Start new attempt on server
              await _startExamAttempt();
              if (_disposed) return;
              
              _saveLocalDataThrottled();
              _startExamNormally();
            },
            child: const Text("Start New"),
          ),
          ElevatedButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.pop(context);

              // Resume previous attempt
              loadLocalData();
              startTimer();
              _startAutoTimers();
            },
            child: const Text("Resume"),
          ),
        ],
      ),
    );
  }

  void _startExamNormally() {
    if (_disposed) return;
    
    loadLocalData();
    startTimer();
    _startAutoTimers();
  }

  void loadLocalData() {
    if (_disposed) return;
    
    final saved = examBox.get(attemptId);
    if (mounted) {
      setState(() {
        studentAnswers = saved != null
            ? Map<String, dynamic>.from(saved['answers'] ?? {})
            : {};
        flaggedQuestions = saved != null
            ? Set<String>.from(saved['flaggedQuestions'] ?? [])
            : {};
        _remainingSeconds = saved != null
            ? (saved['remainingTime'] ?? examDurationSeconds).toInt()
            : examDurationSeconds ?? (60 * 30);
        submitted = saved != null ? saved['submitted'] ?? false : false;
        flaggedSuspicious = saved != null ? saved['flagged'] ?? false : false;
      });
    }

    // Update resume reference asynchronously
    examBox.put('${widget.examId}_${widget.studentId}', {
      'attemptId': attemptId,
      'attemptStartTime': attemptStartTime?.toIso8601String(),
      'submitted': submitted,
    });
  }

  /// Throttled save to prevent overwhelming storage
  void _saveLocalDataThrottled() {
    if (_disposed) return;
    
    final now = DateTime.now();
    if (_lastAutoSaveTime != null && 
        now.difference(_lastAutoSaveTime!).inSeconds < 5) {
      return; // Skip if saved less than 5 seconds ago
    }
    
    _lastAutoSaveTime = now;
    _saveLocalDataImmediate();
  }

  void _saveLocalDataImmediate() {
    if (_disposed) return;
    
    if (attemptId == null) {
      if (kDebugMode) {
        debugPrint('⚠️ Cannot save local data - no attempt ID yet');
      }
      return;
    }

    // Save asynchronously (non-blocking)
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

    examBox.put('${widget.examId}_${widget.studentId}', {
      'attemptId': attemptId,
      'attemptStartTime': attemptStartTime?.toIso8601String(),
      'submitted': submitted,
    });
  }

  void startTimer() {
    if (_disposed) return;
    
    _cancelTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || !mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 0) {
        _cancelTimer();
        if (!submitted) submitExam(autoSubmitted: true);
      } else {
        _remainingSeconds--;
      }

      // Auto-save every 30 seconds
      if (_remainingSeconds % 30 == 0 && !submitted) {
        _saveExamProgress();
        _saveLocalDataThrottled();
      }

      if (mounted) setState(() {});
    });
  }

  void _startAutoTimers() {
    if (_disposed) return;
    
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      if (_disposed || !mounted || submitted) {
        t.cancel();
        return;
      }
      _saveLocalDataThrottled();
    });

    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (_disposed || !mounted || submitted) {
        t.cancel();
        return;
      }
      _saveExamProgress();
    });
  }

  String formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _saveExamProgress() async {
    if (_disposed) return;
    
    final box = examBox;
    box.put('${widget.examId}_${widget.studentId}_progress', {
      'answers': studentAnswers,
      'timeLeft': _remainingSeconds,
      'inProgress': !submitted,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _checkExamStatus() async {
    if (_disposed) return;
    
    try {
      final box = examBox;
      final savedData = box.get('${widget.examId}_${widget.studentId}_progress');
      
      if (savedData != null && 
          savedData['inProgress'] == true && 
          (savedData['submitted'] == null || savedData['submitted'] == false)) {
        if (_disposed || !mounted) return;
        if (Navigator.of(context).canPop()) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Resume Exam?'),
            content: const Text('You have an unfinished exam. Would you like to continue where you left off?'),
            actions: [
              TextButton(
                onPressed: () {
                  if (!mounted) return;
                  Navigator.pop(context);
                  _resumeExam(savedData);
                },
                child: const Text('Resume'),
              ),
              TextButton(
                onPressed: () {
                  if (!mounted) return;
                  Navigator.pop(context);
                  submitExam(autoSubmitted: false);
                },
                child: const Text('Submit Now'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error checking exam status: $e');
      }
    }
  }

  void _resumeExam(Map savedData) {
    if (_disposed || !mounted) return;
    
    setState(() {
      studentAnswers = Map<String, dynamic>.from(savedData['answers'] ?? {});
      _remainingSeconds = savedData['timeLeft'] ?? _remainingSeconds;
    });
  }

  Future<void> submitExam({bool autoSubmitted = false}) async {
    if (_disposed || !mounted) return;

    if (attemptId == null) {
      if (kDebugMode) {
        debugPrint('❌ Cannot submit - no attempt ID');
      }
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No active exam attempt')),
      );
      return;
    }

    if (mounted) {
      setState(() => syncing = true);
    }

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
        durationTakenSeconds = (examDurationSeconds ?? (60 * 30)) - _remainingSeconds;
      }

      if (kDebugMode) {
        debugPrint('⏱️ Duration taken: $durationTakenSeconds seconds');
      }

      // Format answers according to API spec (parallel processing)
      final formattedAnswers = <Map<String, dynamic>>[];
      
      for (var entry in studentAnswers.entries) {
        final questionId = entry.key;
        final answer = entry.value;

        final question = questions.firstWhere(
          (q) => q['id'] == questionId,
          orElse: () => {},
        );

        final itemId = question['itemId'];
        final questionType = question['type'];

        if (itemId == null) {
          if (kDebugMode) {
            debugPrint('⚠️ No item_id found for question $questionId');
          }
          continue;
        }

        String formattedAnswer;
        if (questionType == 'mcq' && answer is List) {
          formattedAnswer = answer.join(',');
          if (kDebugMode) {
            debugPrint('   MCQ answer: $formattedAnswer (${answer.length} selections)');
          }
        } else {
          formattedAnswer = answer.toString();
        }

        formattedAnswers.add({
          'item_id': itemId,
          'answer': formattedAnswer,
        });
      }

      if (kDebugMode) {
        debugPrint('📤 Submitting ${formattedAnswers.length} answers...');
      }

      // Submit to server
      final result = await ApiService.submitExamAttempt(
        attemptId: attemptId!,
        durationTakenSeconds: durationTakenSeconds,
        answers: formattedAnswers,
      );

      if (_disposed) return;

      if (result == null || result['error'] != null) {
        final errorMsg = result?['error'] ?? 'Failed to submit exam';
        if (kDebugMode) {
          debugPrint('❌ Submission error: $errorMsg');
        }

        if (mounted && Navigator.canPop(context)) Navigator.pop(context);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Submission failed: $errorMsg')),
          );
        }

        if (mounted) {
          setState(() => syncing = false);
        }
        return;
      }

      // Extract score from response (save but don't show yet)
      final attemptData = result['attempt'];
      final score = attemptData?['score'] ?? 0;

      if (kDebugMode) {
        debugPrint('✅ Exam submitted successfully - Score: $score (hidden from student)');
      }

      // Calculate local scores for storage
      num totalMarks = 0;
      for (var q in questions) {
        totalMarks += (q['marks'] ?? 1).toInt();
      }

      bool synced = true;
      final now = DateTime.now().toIso8601String();
      final attemptKey = 'attempt_${widget.examId}_${widget.studentId}';
      final metaKey = 'meta_${widget.examId}_${widget.studentId}';
      final existingMeta = examBox.get(metaKey) as Map? ?? {};

      // Save asynchronously (parallel operations)
      await Future.wait([
        examBox.put(attemptKey, {
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
          'completedAt': now,
          'questions': questions,
          'recordType': 'attempt',
        }),
        examBox.put(metaKey, {
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
          'resultsReleased': false,
          'synced': synced,
          'recordType': 'exam',
          'completedAt': now,
        }),
      ]);

      if (_disposed) return;

      if (mounted) {
        setState(() {
          syncing = false;
          submitted = true;
        });
      }

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (_disposed || !mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 10),
              Text(
                autoSubmitted ? "Exam Auto-Submitted" : "Exam Submitted",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            autoSubmitted
                ? "Your exam was automatically submitted after multiple interruptions. "
                  "You can view your results once they are released by your teacher."
                : "Your exam has been successfully submitted! "
                  "You can view your results once they are released by your teacher.",
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (!mounted) return;
                Navigator.pop(context);
                navigateWithFade(
                  context,
                  StudentDashboard(studentId: widget.studentId),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text("Back to Dashboard", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      if (_disposed) return;
      
      if (kDebugMode) {
        debugPrint('⚠️ Exception during exam submission: $e');
        debugPrint('Stack: $stackTrace');
      }

      if (mounted) {
        setState(() => syncing = false);
      }

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting exam: $e')),
        );
      }
    }
  }

  // -------------------------
  // Lifecycle & Anti-Cheat
  // -------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !mounted || submitted) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _handleExitAttempt();
        break;

      case AppLifecycleState.resumed:
        _lastExitEventTime = DateTime.now();
        if (!submitted && (_timer == null || !(_timer?.isActive ?? false))) {
          startTimer();
        }
        _secureExamEnvironment();
        _saveLocalDataThrottled();
        _checkExamStatus();
        break;

      default:
        break;
    }
  }

  Future<bool> _onWillPop() async {
    if (_disposed || submitted) return true;
    _handleExitAttempt();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Back navigation is disabled during the exam."),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return false;
  }

  Future<void> _handleExitAttempt() async {
    if (_disposed || !mounted || submitted || _isWarningDialogVisible) return;

    final now = DateTime.now();

    // Debounce
    if (_lastExitEventTime != null &&
        now.difference(_lastExitEventTime!).inSeconds < 2) {
      return;
    }
    _lastExitEventTime = now;

    flaggedSuspicious = true;
    showSuspiciousBanner = true;

    _exitCount = (_exitCount + 1).clamp(0, 3);

    _saveLocalDataThrottled();
    _saveExamProgress();
    
    // CRITICAL FIX: Pause timer during warning dialog
    final timerWasActive = _timer?.isActive ?? false;
    _cancelTimer();

    if (kDebugMode) {
      debugPrint("⚠️ Exit attempt #$_exitCount detected. Timer paused.");
    }

    if (_exitCount >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_disposed || !mounted) return;
        await submitExam(autoSubmitted: true);
      });
      return;
    }

    final message = _exitCount == 1
        ? "You left the exam window. Please return immediately."
        : "⚠️ You left again. One more time will auto-submit your exam.";

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || !mounted) return;
      await _showWarningDialog(message, timerWasActive);
    });
  }

  Future<void> _showWarningDialog(String message, bool restartTimer) async {
    if (_disposed || !mounted || _isWarningDialogVisible) return;

    _isWarningDialogVisible = true;
    _isExamPausedOverlayVisible = true;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => WillPopScope(
          onWillPop: () async => false,
          child: Stack(
            children: [
              if (_isExamPausedOverlayVisible)
                const Opacity(
                  opacity: 0.6,
                  child: ModalBarrier(dismissible: false, color: Colors.black54),
                ),
              Center(
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        _exitCount == 1
                            ? Icons.warning_amber_rounded
                            : Icons.report_problem_rounded,
                        color: _exitCount == 1 ? Colors.amberAccent : Colors.deepOrange,
                      ),
                      const SizedBox(width: 10),
                      const Text("Exam Paused"),
                    ],
                  ),
                  content: Text(message),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.pop(context);
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
    } finally {
      _isWarningDialogVisible = false;
      _isExamPausedOverlayVisible = false;

      // CRITICAL FIX: Resume timer after dialog closes
      if (!_disposed && !submitted && restartTimer) {
        startTimer();
        if (kDebugMode) {
          debugPrint("✅ Timer resumed after warning dialog");
        }
      }
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _startFocusCheck() {
    if (_disposed) return;
    
    _focusCheckTimer?.cancel();
    _focusCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed || !mounted || submitted) return;
      final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (!isForeground) {
        if (kDebugMode) {
          debugPrint("🚨 Focus lost — possible notification or swipe down detected.");
        }
        _handleExitAttempt();
      }
    });
  }

  void _listenForScreenshots() {
    if (_disposed) return;
    
    _screenshotChannel.setMethodCallHandler((call) async {
      if (_disposed) return;
      
      if (call.method == "onScreenshot") {
        if (kDebugMode) {
          debugPrint("📸 Screenshot detected!");
        }
        if (!submitted) {
          await _handleExitAttempt();
        }
      }
    });
  }

  void _startOverlayCheck() {
    if (_disposed) return;
    
    _overlayCheckTimer?.cancel();
    _overlayCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_disposed || !mounted || submitted) return;
      if (_isWarningDialogVisible) return;

      bool hasOverlay = false;
      try {
        hasOverlay = await _overlayChannel
                .invokeMethod<bool>('checkOverlayPermission')
                .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
            false;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Overlay detection failed: $e');
        }
      }

      if (kDebugMode) {
        debugPrint('🔍 Overlay active? $hasOverlay');
      }

      if (hasOverlay && mounted && !_isWarningDialogVisible && !_disposed) {
        await _showOverlayWarning();
      }
    });
  }

  Future<void> _showOverlayWarning() async {
    if (_disposed || !mounted || _isWarningDialogVisible) return;
    
    _isWarningDialogVisible = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Overlay Detected"),
          content: const Text(
            "Screen overlays (e.g., chat heads, recorders) can interfere with your exam. "
            "Please close them to continue.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text("OK, Got it"),
            ),
          ],
        ),
      );
    } finally {
      _isWarningDialogVisible = false;
    }
  }

// -------------------------
// Split Screen Detection
// -------------------------
void _listenForSplitScreen() {
  if (_disposed) return;
  
  _splitScreenChannel.setMethodCallHandler((call) async {
    if (_disposed || !mounted) return;
    
    if (call.method == "onSplitScreenChanged") {
      final isInSplitScreen = call.arguments['isInSplitScreen'] as bool? ?? false;
      
      if (kDebugMode) {
        debugPrint("📱 Split screen status changed: $isInSplitScreen");
      }
      
      if (isInSplitScreen && !submitted && !_isSplitScreenWarningVisible) {
        if (mounted) {
          setState(() {
            _isInSplitScreen = true;
          });
        }
        await _handleSplitScreenDetected();
      } else if (!isInSplitScreen) {
        if (mounted) {
          setState(() {
            _isInSplitScreen = false;
          });
        }
      }
    }
  });
  
  _checkSplitScreenStatus();
}

void _startSplitScreenCheck() {
  if (_disposed) return;
  
  Timer.periodic(const Duration(seconds: 3), (timer) {
    if (_disposed || !mounted || submitted) {
      timer.cancel();
      return;
    }
    _checkSplitScreenStatus();
  });
}

Future<void> _checkSplitScreenStatus() async {
  if (_disposed || !mounted || _isSplitScreenWarningVisible) return;
  
  try {
    final isInSplitScreen = await _splitScreenChannel
        .invokeMethod<bool>('checkSplitScreen')
        .timeout(const Duration(seconds: 2), onTimeout: () => false) ?? false;
    
    if (kDebugMode) {
      debugPrint('🔍 Split screen check: $isInSplitScreen');
    }
    
    // FIX: Only trigger if state changed
    if (isInSplitScreen && !_isInSplitScreen && !submitted && mounted) {
      setState(() {
        _isInSplitScreen = true;
      });
      await _handleSplitScreenDetected();
    } else if (!isInSplitScreen && _isInSplitScreen && mounted) {
      setState(() {
        _isInSplitScreen = false;
      });
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Split screen detection failed: $e');
    }
  }
}

Future<void> _handleSplitScreenDetected() async {
  if (_disposed || !mounted || submitted || _isWarningDialogVisible || _isSplitScreenWarningVisible) return;
  
  if (kDebugMode) {
    debugPrint("🚨 Split screen detected during exam!");
  }
  
  flaggedSuspicious = true;
  showSuspiciousBanner = true;
  _exitCount = (_exitCount + 1).clamp(0, 3);
  
  _saveLocalDataThrottled();
  
  final timerWasActive = _timer?.isActive ?? false;
  _cancelTimer();
  
  if (_exitCount >= 3) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || !mounted) return;
      await submitExam(autoSubmitted: true);
    });
    return;
  }
  
  final message = _exitCount == 1
      ? "⚠️ Split screen detected! Please exit split screen mode immediately."
      : "⚠️ Split screen detected again! One more violation will auto-submit your exam.";
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (_disposed || !mounted) return;
    await _showSplitScreenWarning(message, timerWasActive);
  });
}

Future<void> _showSplitScreenWarning(String message, bool restartTimer) async {
  if (_disposed || !mounted || _isWarningDialogVisible || _isSplitScreenWarningVisible) return;
  
  _isWarningDialogVisible = true;
  _isSplitScreenWarningVisible = true; // FIX: Prevent duplicate dialogs
  
  try {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [ // FIX: Remove const
              Icon(
                Icons.splitscreen,
                color: Colors.red,
                size: 32,
              ),
              SizedBox(width: 10),
              Text("Split Screen Detected!"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Text(
                  "Please exit split screen mode before continuing. "
                  "Using split screen during an exam is prohibited.",
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                // FIX: Add debouncing and better error handling
                try {
                  final stillInSplitScreen = await _splitScreenChannel
                      .invokeMethod<bool>('checkSplitScreen')
                      .timeout(
                        const Duration(seconds: 3),
                        onTimeout: () => false,
                      ) ?? false;
                  
                  if (!mounted) return;
                  
                  if (stillInSplitScreen) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please exit split screen mode first!'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    // Don't close dialog - keep it open
                  } else {
                    // Successfully exited split screen
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('⚠️ Error checking split screen in dialog: $e');
                  }
                  if (!mounted) return;
                  
                  // Assume they exited if check fails
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text("I've Exited Split Screen"),
            ),
          ],
        ),
      ),
    );
  } finally {
    _isWarningDialogVisible = false;
    _isSplitScreenWarningVisible = false; // FIX: Reset flag
    
    if (!_disposed && !submitted && restartTimer) {
      startTimer();
      if (kDebugMode) {
        debugPrint("✅ Timer resumed after split screen warning");
      }
    }
    
    // FIX: Verify split screen status after dialog closes
    if (!_disposed && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_disposed && mounted) {
          _checkSplitScreenStatus();
        }
      });
      
      setState(() {});
    }
  }
}


  void _cancelTimer() {
    _timer?.cancel();
    _autoSaveTimer?.cancel();
    _autoSyncTimer?.cancel();
    _overlayCheckTimer?.cancel();
    _focusCheckTimer?.cancel();
  }

  double getAnswerProgress() {
    if (questions.isEmpty) return 0.0;
    int answeredCount = studentAnswers.entries
        .where((entry) => questions.any(
            (q) => q['id'] == entry.key &&
                entry.value != null &&
                ((entry.value is List && (entry.value as List).isNotEmpty) ||
                 (entry.value is! List && entry.value.toString().isNotEmpty))))
        .length;
    return answeredCount / questions.length;
  }

  Map<String, dynamic> getQuestionTypeInfo(String type, {String? originalType}) {
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

  void _navigateToQuestion(int index) {
    if (_disposed || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_pageController.hasClients || !_scrollController.hasClients) return;
    setState(() => _currentQuestionIndex = index);

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    final double screenWidth = MediaQuery.of(context).size.width;
    const double itemWidth = 58;
    double targetScrollOffset =
        (index * itemWidth) - screenWidth / 2 + (itemWidth / 2);
    if (targetScrollOffset < 0) targetScrollOffset = 0;

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        targetScrollOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget buildQuestionNavigation() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final q = questions[index];
          final answer = studentAnswers[q['id']];
          final answered = answer != null &&
              ((answer is List && answer.isNotEmpty) ||
               (answer is! List && answer.toString().isNotEmpty));
          final flagged = flaggedQuestions.contains(q['id']);
          final isCurrent = _currentQuestionIndex == index;

          Color color;
          if (isCurrent) {
            color = Colors.blueAccent;
          } else if (flagged) {
            color = Colors.orange;
          } else if (answered) {
            color = Colors.green;
          } else {
            color = Colors.grey.shade300;
          }

          return GestureDetector(
            onTap: () => _navigateToQuestion(index),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
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
                            const Padding(
                              padding: EdgeInsets.all(8.0),
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
                            const Padding(
                              padding: EdgeInsets.all(8.0),
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

    // Regular exam mode
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: getAnswerProgress(),
                backgroundColor: Colors.grey[300],
                color: Colors.blueAccent,
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Progress: ${(getAnswerProgress() * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Time Left: ${formatTime(_remainingSeconds)}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 60 ? Colors.red : Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        buildQuestionNavigation(),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: questions.length,
            onPageChanged: (index) {
              if (mounted) {
                setState(() => _currentQuestionIndex = index);
              }
            },
            itemBuilder: (context, index) {
              final q = questions[index];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: QuestionWidget(
                  key: ValueKey(q['id']),
                  question: q,
                  submitted: submitted,
                  studentAnswers: studentAnswers,
                  flaggedQuestions: flaggedQuestions,
                  onAnswerChanged: (id, val) {
                    if (mounted) {
                      setState(() {
                        studentAnswers[id] = val;
                      });
                    }
                    _saveLocalDataThrottled();
                    _saveExamProgress();
                  },
                  onFlagToggled: (id) {
                    if (mounted) {
                      setState(() {
                        if (flaggedQuestions.contains(id)) {
                          flaggedQuestions.remove(id);
                        } else {
                          flaggedQuestions.add(id);
                        }
                      });
                    }
                    _saveLocalDataThrottled();
                  },
                  getQuestionTypeInfo: getQuestionTypeInfo,
                ),
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
    if (confirm == true) await submitExam();
  }

  @override
  void dispose() {
    _disposed = true;
    
    // Cancel all timers
    _focusCheckTimer?.cancel();
    _overlayCheckTimer?.cancel();
    _cancelTimer();

    // Proper cleanup for split screen detection
    _splitScreenChannel.setMethodCallHandler(null);
    _splitScreenSubscription?.cancel();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    // Dispose controllers
    _pageController.dispose();
    _scrollController.dispose();
    _questionScrollController.dispose();

    // Final save before disposal
    _saveLocalDataImmediate();

    // Cleanup security
    WakelockPlus.disable();
    FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    super.dispose();
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
              const Text('Failed to load exam', style: TextStyle(fontSize: 18)),
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
              automaticallyImplyLeading: false,
              title: Text("${widget.subject} Exam"),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Time Left: ${formatTime(_remainingSeconds)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 60 ? Colors.red : Colors.white,
                    ),
                  ),
                ),
              ),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
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

// ------------------------ QUESTION WIDGET ------------------------

class QuestionWidget extends StatefulWidget {
  final Map<String, dynamic> question;
  final bool submitted;
  final Map<String, dynamic> studentAnswers;
  final Set<String> flaggedQuestions;
  final Function(String id, dynamic val) onAnswerChanged;
  final Function(String id) onFlagToggled;
  final Function(String type, {String? originalType}) getQuestionTypeInfo;

  const QuestionWidget({
    super.key,
    required this.question,
    required this.submitted,
    required this.studentAnswers,
    required this.flaggedQuestions,
    required this.onAnswerChanged,
    required this.onFlagToggled,
    required this.getQuestionTypeInfo,
  });

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<QuestionWidget>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    final id = widget.question['id'];
    controller = TextEditingController(
        text: widget.studentAnswers[id]?.toString() ?? '');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = widget.question;
    final isFlagged = widget.flaggedQuestions.contains(q['id']);
    final typeInfo = widget.getQuestionTypeInfo(
      q['type'] ?? 'unknown',
      originalType: q['originalType'],
    );

    return SingleChildScrollView(
      child: Card(
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
                    child: Text(
                      q['question'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFlagged ? Icons.flag : Icons.outlined_flag,
                      color: isFlagged ? Colors.orange : Colors.grey,
                    ),
                    onPressed: widget.submitted
                        ? null
                        : () => widget.onFlagToggled(q['id']),
                  )
                ],
              ),
              const SizedBox(height: 12),
              if (q['type'] == 'mcq')
                if (q['choices'] != null && q['choices'] is List && q['choices'].isNotEmpty)
                  ...q['choices'].map<Widget>((opt) {
                    final optKey = opt['key'] ?? '';
                    final optText = opt['text'] ?? '';

                    final selectedAnswers = widget.studentAnswers[q['id']] is List
                        ? List<String>.from(widget.studentAnswers[q['id']])
                        : (widget.studentAnswers[q['id']] != null &&
                                widget.studentAnswers[q['id']].toString().isNotEmpty)
                            ? [widget.studentAnswers[q['id']].toString()]
                            : <String>[];

                    final isSelected = selectedAnswers.contains(optKey);

                    return CheckboxListTile(
                      title: Text(optText),
                      value: isSelected,
                      onChanged: widget.submitted
                          ? null
                          : (bool? checked) {
                              if (checked == true) {
                                selectedAnswers.add(optKey);
                              } else {
                                selectedAnswers.remove(optKey);
                              }
                              widget.onAnswerChanged(
                                  q['id'], selectedAnswers.isEmpty ? null : selectedAnswers);
                            },
                      activeColor: Colors.blueAccent,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }).toList()
                else
                  const Padding(
                    padding: EdgeInsets.all(8.0),
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
                      groupValue: widget.studentAnswers[q['id']] as String?,
                      onChanged: widget.submitted
                          ? null
                          : (String? value) {
                              widget.onAnswerChanged(q['id'], value);
                            },
                      activeColor: Colors.blueAccent,
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList()
                else
                  const Padding(
                    padding: EdgeInsets.all(8.0),
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
                      key: PageStorageKey(q['id']),
                      controller: controller,
                      enabled: !widget.submitted,
                      enableInteractiveSelection: !widget.submitted,
                      maxLines: q['type'] == 'essay' ? 5 : 1,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: q['type'] == 'enumeration'
                            ? 'List answers separated by commas'
                            : 'Your answer...',
                      ),
                      onChanged: widget.submitted
                          ? null
                          : (val) => widget.onAnswerChanged(q['id'], val),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
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
