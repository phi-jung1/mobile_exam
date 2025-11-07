import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pie_chart/pie_chart.dart';
import 'package:confetti/confetti.dart';
import '../services/api_service.dart';

// 🧭 Navigation Helper
Future<void> navigateToDashboard(BuildContext context, String studentId) async {
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

enum FilterOption { all, correct, incorrect }

class ResultsScreen extends StatefulWidget {
  final String attemptId;  // ✅ This is the attempt ID from the exam attempt
  final String studentId;
  final String? examTitle;
  final String? subject;

  const ResultsScreen({
    super.key,
    required this.attemptId,
    required this.studentId,
    this.examTitle,
    this.subject,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with TickerProviderStateMixin {
  late final Box examBox;
  late final ScrollController _scrollController;
  late final ConfettiController _confettiController;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  // ✅ NEW: Use results array from API (contains isCorrect and points)
  List<Map<String, dynamic>> results = [];
  Map<String, dynamic>? statistics;
  Map<String, dynamic>? attemptInfo;
  
  // Legacy support for cache
  Map<String, dynamic> studentAnswers = {};
  List<Map<String, dynamic>> questions = [];
  
  bool flagged = false;
  bool loaded = false;
  bool showFAB = false;
  bool _confettiPlayed = false;
  bool _disposed = false;
  FilterOption filter = FilterOption.all;
  String? errorMessage;
  int? score;
  int? totalMarks;
  int correctCount = 0;
  int incorrectCount = 0;
  int unansweredCount = 0;


  @override
  void initState() {
    super.initState();
    examBox = Hive.box('examBox');
    
    _scrollController = ScrollController()
      ..addListener(() {
        if (_disposed || !mounted) return;
        setState(() => showFAB = _scrollController.offset > 350);
      });
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    
    _loadExamResults();
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    _animationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadExamResults() async {
    if (_disposed || !mounted) return;

    // Try API first
    bool loadedFromAPI = await _loadExamResultsFromAPI();
    
    if (_disposed || !mounted) return;

    // If API failed or returned no data, try cache
    if (!loadedFromAPI || (results.isEmpty && questions.isEmpty)) {
      if (kDebugMode) {
        debugPrint('⚠️ API load incomplete, trying local cache...');
      }
      await _loadExamResultsFromCache();
    }
    
    if (_disposed || !mounted) return;

    if (loaded && (results.isNotEmpty || questions.isNotEmpty)) {
      _animationController.forward();
      _checkAndPlayConfetti();
    }
  }

  Future<bool> _loadExamResultsFromAPI() async {
    if (_disposed || !mounted) return false;

    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint('📡 LOADING RESULTS FROM API');
        debugPrint('   Attempt ID: ${widget.attemptId}');
        debugPrint('   Student ID: ${widget.studentId}');
      }
      
      final attemptId = int.tryParse(widget.attemptId);
      if (attemptId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Invalid attempt ID format: ${widget.attemptId}');
        }
        return false;
      }
      
      final apiResponse = await ApiService.fetchExamResults(attemptId: attemptId);
      
      if (_disposed || !mounted) return false;

      if (apiResponse != null && apiResponse['error'] == null) {
        if (kDebugMode) {
          debugPrint('✅ API Response received');
          debugPrint('   Response keys: ${apiResponse.keys.toList()}');
        }
        
        // ✅ Extract attempt info (score, total marks, etc.)
        if (apiResponse['attempt'] != null) {
          attemptInfo = Map<String, dynamic>.from(apiResponse['attempt']);
          score = (attemptInfo!['score'] as num?)?.toInt();
          totalMarks = (attemptInfo!['total_marks'] as num?)?.toInt();
          flagged = attemptInfo!['flagged'] ?? false;
          
          if (kDebugMode) {
            debugPrint('   📊 Attempt Info:');
            debugPrint('      Score: $score / $totalMarks');
            debugPrint('      Flagged: $flagged');
          }
        }
        
        // ✅ Extract statistics (pre-calculated from backend)
        if (apiResponse['statistics'] != null) {
          statistics = Map<String, dynamic>.from(apiResponse['statistics']);
          
          // 🩹 FIX: safely convert any double values to int
          correctCount = (statistics!['correctAnswers'] as num?)?.toInt() ?? 0;
          incorrectCount = (statistics!['incorrectAnswers'] as num?)?.toInt() ?? 0;
          unansweredCount = (statistics!['unanswered'] as num?)?.toInt() ?? 0;

          if (kDebugMode) {
            debugPrint('   📈 Statistics:');
            debugPrint('      Correct: $correctCount');
            debugPrint('      Incorrect: $incorrectCount');
            debugPrint('      Unanswered: $unansweredCount');
          }
        }

        
        // ✅ CRITICAL: Extract results array (NEW API FORMAT)
        if (apiResponse['results'] != null && apiResponse['results'] is List) {
          results = List<Map<String, dynamic>>.from(apiResponse['results']);
          
          if (kDebugMode) {
            debugPrint('   ✅ Results array found: ${results.length} items');
            debugPrint('   Sample result structure:');
            if (results.isNotEmpty) {
              final sample = results[0];
              debugPrint('      Keys: ${sample.keys.toList()}');
              debugPrint('      Has isCorrect: ${sample.containsKey('isCorrect')}');
              debugPrint('      Has pointsAwarded: ${sample.containsKey('pointsAwarded')}');
              debugPrint('      Has correctAnswer: ${sample.containsKey('correctAnswer')}');
              debugPrint('      correctAnswer value: ${sample['correctAnswer']}');
            }
          }
          
          // ✅ Also populate legacy structures for backward compatibility
          questions = results.map((r) => {
            'id': r['id'],
            'itemId': r['itemId'],
            'question': r['question'],
            'type': r['type'],
            'choices': r['choices'],
            'correct': r['correctAnswer'], // May be null (hidden by backend)
            'marks': r['maxPoints'],
            'isCorrect': r['isCorrect'],
            'pointsAwarded': r['pointsAwarded'],
            'maxPoints': r['maxPoints'],
          }).toList();
          
          studentAnswers = Map.fromEntries(
            results.map((r) => MapEntry(
              r['id'] as String,
              r['studentAnswer'],
            )),
          );
          
          if (kDebugMode) {
            debugPrint('   ✅ Converted to legacy format:');
            debugPrint('      Questions: ${questions.length}');
            debugPrint('      Answers: ${studentAnswers.length}');
          }
        }
        // Fallback to legacy format if results array not available
        else {
          if (kDebugMode) {
            debugPrint('   ⚠️ No results array, trying legacy format...');
          }
          
          if (apiResponse['questions'] != null && apiResponse['questions'] is List) {
            questions = List<Map<String, dynamic>>.from(apiResponse['questions']);
          }
          
          if (apiResponse['answers'] != null && apiResponse['answers'] is Map) {
            studentAnswers = Map<String, dynamic>.from(apiResponse['answers']);
          }
          
          if (kDebugMode) {
            debugPrint('   📊 Legacy format:');
            debugPrint('      Questions: ${questions.length}');
            debugPrint('      Answers: ${studentAnswers.length}');
          }
        }
        
        if (mounted) {
          setState(() {
            loaded = true;
            errorMessage = null;
          });
        }
        
        if (kDebugMode) {
          debugPrint('═══════════════════════════════════════════════════════');
        }
        
        if (mounted && (results.isNotEmpty || questions.isNotEmpty)) {
          _showSnack("✅ Results loaded from server!");
        }
        
        return results.isNotEmpty || questions.isNotEmpty;
      } else {
        final errorMsg = apiResponse?['error'] ?? 'No results available';
        if (kDebugMode) {
          debugPrint('⚠️ API returned error: $errorMsg');
        }
        
        if (mounted) {
          setState(() => errorMessage = errorMsg);
        }
        return false;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ Exception loading from API: $e');
        debugPrint('   Stack: $stackTrace');
      }
      return false;
    }
  }

  Future<void> _loadExamResultsFromCache() async {
    if (_disposed || !mounted) return;

    try {
      if (kDebugMode) {
        debugPrint('💾 Loading results from cache...');
        debugPrint('   Attempt ID: ${widget.attemptId}');
        debugPrint('   Student ID: ${widget.studentId}');
      }
      
      final allKeys = examBox.keys.cast<String>().toList();
      String? matchingKey;
      
      // Search all records for matching attemptId
      for (var key in allKeys) {
        final record = examBox.get(key);
        if (record is! Map) continue;
        
        final recordAttemptId = record['attemptId']?.toString() ?? 
                               record['attempt']?['attempt_id']?.toString();
        
        if (recordAttemptId == widget.attemptId && 
            record['studentId'] == widget.studentId) {
          matchingKey = key;
          if (kDebugMode) {
            debugPrint('   ✓ Found matching record: $key');
          }
          break;
        }
      }

      if (matchingKey == null) {
        if (kDebugMode) {
          debugPrint('⚠️ No matching cached results found');
        }
        
        if (_disposed || !mounted) return;
        setState(() {
          loaded = true;
          errorMessage = errorMessage ?? 
              "Results not available offline. Please check your connection.";
        });
        return;
      }

      final cachedRecord = Map<String, dynamic>.from(examBox.get(matchingKey));
      
      if (kDebugMode) {
        debugPrint('✅ Using cached record from: $matchingKey');
      }

      if (_disposed || !mounted) return;

      setState(() {
        // Extract results array if available
        if (cachedRecord['results'] != null && cachedRecord['results'] is List) {
          results = List<Map<String, dynamic>>.from(cachedRecord['results']);
        }
        
        // Extract legacy format
        final rawAnswers = cachedRecord['answers'] ?? 
                          cachedRecord['studentAnswers'] ?? {};
        studentAnswers = Map<String, dynamic>.from(rawAnswers);
        
        final rawQuestions = cachedRecord['questions'] ?? [];
        questions = (rawQuestions as List)
            .map((q) => Map<String, dynamic>.from(q))
            .toList();
        
        // Extract score and stats
        score = cachedRecord['score'] ?? cachedRecord['attempt']?['score'];
        totalMarks = cachedRecord['totalMarks'] ?? 
                    cachedRecord['total_marks'] ??
                    cachedRecord['attempt']?['total_marks'];
        
        if (cachedRecord['statistics'] != null) {
          statistics = Map<String, dynamic>.from(cachedRecord['statistics']);
        }
        
        flagged = cachedRecord['flagged'] ?? false;
        loaded = true;
        errorMessage = null;
      });
      
      if (kDebugMode) {
        debugPrint('✅ Loaded from cache:');
        debugPrint('   Results: ${results.length}');
        debugPrint('   Questions: ${questions.length}');
        debugPrint('   Answers: ${studentAnswers.length}');
        debugPrint('   Score: $score${totalMarks != null ? " / $totalMarks" : ""}');
      }
      
      if (mounted) {
        _showSnack("📱 Results loaded from offline cache");
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ Error loading from cache: $e');
        debugPrint('   Stack: $stackTrace');
      }
      if (_disposed || !mounted) return;
      setState(() {
        loaded = true;
        errorMessage = errorMessage ?? "Failed to load results from cache.";
      });
    }
  }

  void _checkAndPlayConfetti() {
    if (_disposed || !mounted || _confettiPlayed) return;

    final correctCount = getCorrectCount();
    final total = getTotalQuestions();
    final scorePercent = total == 0 ? 0 : ((correctCount / total) * 100).round();

    if (scorePercent >= 75) {
      _confettiPlayed = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_disposed || !mounted) return;
        _confettiController.play();
        _showSnack("🎉 Great job! You passed this exam!");
      });
    }
  }

  void _showSnack(String message) {
    if (_disposed || !mounted) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  // ✅ Helper to get display text for answers (converts key to text)
  String getAnswerDisplayText(Map<String, dynamic> question, dynamic answerValue) {
    if (answerValue == null || answerValue.toString().isEmpty) {
      return "No answer provided";
    }

    final answerStr = answerValue.toString();
    
    // For MCQ/True-False, convert key to text
    if ((question['type'] == 'mcq' || question['type'] == 'true_false') && 
        question['choices'] != null) {
      final choices = question['choices'] as List;
      
      final choice = choices.firstWhere(
        (c) => c['key'].toString().toLowerCase() == answerStr.toLowerCase(),
        orElse: () => {'text': answerStr},
      );
      return choice['text'].toString();
    }
    
    return answerStr;
  }

  int getTotalQuestions() {
    // Always use actual data first
    if (results.isNotEmpty) return results.length;
    if (questions.isNotEmpty) return questions.length;
    
    // Fallback to statistics - FIXED to handle double values
    if (statistics != null && statistics!['totalQuestions'] != null) {
      return (statistics!['totalQuestions'] as num?)?.toInt() ?? 0;
    }
    
    return 0;
  }

  int getCorrectCount() {
    // Prioritize backend statistics if available (more reliable)
    if (statistics != null && statistics!['correctAnswers'] != null) {
      return (statistics!['correctAnswers'] as num?)?.toInt() ?? 0;
    }
    
    // Calculate from actual results data
    if (results.isNotEmpty) {
      return results.where((r) => r['isCorrect'] == true).length;
    }
    
    if (questions.isNotEmpty) {
      return questions.where((q) {
        if (q['isCorrect'] != null) return q['isCorrect'] == true;
        final correct = q['correct']?.toString().trim().toLowerCase();
        final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
        return correct != null && correct == answer && correct.isNotEmpty;
      }).length;
    }
    
    return 0;
  }

  int getIncorrectCount() {
    // Prioritize backend statistics if available (more reliable)
    if (statistics != null && statistics!['incorrectAnswers'] != null) {
      return (statistics!['incorrectAnswers'] as num?)?.toInt() ?? 0;
    }
    
    // Calculate from actual results data
    // FIXED: Only count false, NOT null (null = pending grading)
    if (results.isNotEmpty) {
      return results.where((r) {
        final hasAnswer = r['studentAnswer'] != null && 
                         r['studentAnswer'].toString().isNotEmpty;
        // Only count explicitly false answers, not null
        return hasAnswer && r['isCorrect'] == false;
      }).length;
    }
    
    if (questions.isNotEmpty) {
      return questions.where((q) {
        final answer = studentAnswers[q['id']];
        final hasAnswer = answer != null && answer.toString().isNotEmpty;
        
        if (!hasAnswer) return false;
        
        if (q['isCorrect'] != null) {
          // Only count explicitly false, not null
          return q['isCorrect'] == false;
        }
        
        final correct = q['correct']?.toString().trim().toLowerCase();
        final answerStr = answer.toString().trim().toLowerCase();
        return correct != null && correct != answerStr;
      }).length;
    }
    
    return 0;
  }

  int getUnansweredCount() {
    // Prioritize backend statistics if available (more reliable)
    if (statistics != null && statistics!['unanswered'] != null) {
      return (statistics!['unanswered'] as num?)?.toInt() ?? 0;
    }
    
    // Calculate from actual results data
    if (results.isNotEmpty) {
      return results.where((r) => 
        r['studentAnswer'] == null || r['studentAnswer'].toString().isEmpty
      ).length;
    }
    
    if (questions.isNotEmpty) {
      return questions.where((q) {
        final answer = studentAnswers[q['id']];
        return answer == null || answer.toString().isEmpty;
      }).length;
    }
    
    return 0;
  }

  // NEW: Add method to get pending grading count (isCorrect: null)
  int getPendingGradingCount() {
    if (results.isNotEmpty) {
      return results.where((r) {
        final hasAnswer = r['studentAnswer'] != null && 
                         r['studentAnswer'].toString().isNotEmpty;
        // Count items that are answered but isCorrect is null
        return hasAnswer && r['isCorrect'] == null;
      }).length;
    }
    
    if (questions.isNotEmpty) {
      return questions.where((q) {
        final answer = studentAnswers[q['id']];
        final hasAnswer = answer != null && answer.toString().isNotEmpty;
        return hasAnswer && q['isCorrect'] == null;
      }).length;
    }
    
    return 0;
  }

  List<Map<String, dynamic>> getFilteredQuestions() {
    // Use results array if available
    if (results.isNotEmpty) {
      switch (filter) {
        case FilterOption.correct:
          return results.where((r) => r['isCorrect'] == true).toList();
        case FilterOption.incorrect:
          return results.where((r) => r['isCorrect'] == false).toList();
        case FilterOption.all:
        default:
          return results;
      }
    }
    
    // Fallback to legacy questions
    switch (filter) {
      case FilterOption.correct:
        return questions.where((q) {
          if (q['isCorrect'] != null) return q['isCorrect'] == true;
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct != null && correct == answer;
        }).toList();
      case FilterOption.incorrect:
        return questions.where((q) {
          if (q['isCorrect'] != null) return q['isCorrect'] == false;
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct != null && correct != answer;
        }).toList();
      case FilterOption.all:
      default:
        return questions;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.examTitle ?? "Exam Results"),
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => navigateToDashboard(context, widget.studentId),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Loading results...'),
            ],
          ),
        ),
      );
    }

    final hasData = results.isNotEmpty || questions.isNotEmpty;
    
    if (!hasData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.examTitle ?? "Exam Results"),
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => navigateToDashboard(context, widget.studentId),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  errorMessage ?? 'Detailed results are not available yet.',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
              if (score != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Your Score: $score${totalMarks != null ? " / $totalMarks" : ""}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _loadExamResults(),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => navigateToDashboard(context, widget.studentId),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredQuestions = getFilteredQuestions();
    final correctCount = getCorrectCount();
    final incorrectCount = getIncorrectCount();
    final unansweredCount = getUnansweredCount();
    final total = getTotalQuestions();
    final scorePercent = total == 0 ? 0 : ((correctCount / total) * 100).round();
    final passed = scorePercent >= 75;

    final dataMap = {
      "Correct": correctCount.toDouble(),
      "Incorrect": incorrectCount.toDouble(),
      "Unanswered": unansweredCount.toDouble(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examTitle ?? widget.subject ?? "Exam Results"),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => navigateToDashboard(context, widget.studentId),
        ),
      ),
      floatingActionButton: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: showFAB ? 1 : 0,
        child: showFAB
            ? FloatingActionButton(
                heroTag: "scrollToTop",
                onPressed: () {
                  if (!_disposed && mounted) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                backgroundColor: Colors.indigo,
                child: const Icon(Icons.arrow_upward),
              )
            : null,
      ),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF3F4F8), Color(0xFFECEEF9)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ExamSummaryCard(
                          correctCount: correctCount,
                          incorrectCount: incorrectCount,
                          unansweredCount: unansweredCount,
                          total: total,
                          scorePercent: scorePercent,
                          passed: passed,
                          flagged: flagged,
                          dataMap: dataMap,
                          filter: filter,
                          score: score,
                          totalMarks: totalMarks,
                          onFilterChanged: (f) {
                            if (!_disposed && mounted) {
                              setState(() => filter = f);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: QuestionList(
                          questions: filteredQuestions,
                          studentAnswers: studentAnswers,
                          controller: _scrollController,
                          getAnswerDisplayText: getAnswerDisplayText,
                          useResultsFormat: results.isNotEmpty,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: ElevatedButton.icon(
                          onPressed: () => navigateToDashboard(context, widget.studentId),
                          icon: const Icon(Icons.dashboard),
                          label: const Text("Back to Dashboard"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            minimumSize: const Size(180, 45),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.08,
              numberOfParticles: 40,
              gravity: 0.25,
              shouldLoop: false,
              colors: const [
                Colors.greenAccent,
                Colors.indigo,
                Colors.orange,
                Colors.pink,
                Colors.yellowAccent,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ExamSummaryCard with score display
class ExamSummaryCard extends StatelessWidget {
  final int correctCount, incorrectCount, unansweredCount, total, scorePercent;
  final bool passed, flagged;
  final Map<String, double> dataMap;
  final FilterOption filter;
  final int? score;
  final int? totalMarks;
  final ValueChanged<FilterOption> onFilterChanged;

  const ExamSummaryCard({
    super.key,
    required this.correctCount,
    required this.incorrectCount,
    required this.unansweredCount,
    required this.total,
    required this.scorePercent,
    required this.passed,
    required this.flagged,
    required this.dataMap,
    required this.filter,
    this.score,
    this.totalMarks,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "📊 Exam Results Summary",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _ResultBadge(passed: passed, score: scorePercent),
              ],
            ),
            if (score != null) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Score: $score${totalMarks != null ? " / $totalMarks" : ""}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
            ],
            if (flagged) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "⚠️ App interruption detected during the exam.",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat("Total", total, Colors.black),
                _buildStat("Correct", correctCount, Colors.green),
                _buildStat("Incorrect", incorrectCount, Colors.red),
                _buildStat("Unanswered", unansweredCount, Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: PieChart(
                dataMap: dataMap,
                chartType: ChartType.disc,
                chartRadius: MediaQuery.of(context).size.width * 0.3,
                colorList: [
                  Colors.green.shade400,
                  Colors.red.shade400,
                  Colors.grey.shade400
                ],
                chartValuesOptions: const ChartValuesOptions(
                  showChartValuesInPercentage: true,
                ),
                legendOptions: const LegendOptions(
                  legendPosition: LegendPosition.bottom,
                  showLegendsInRow: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Wrap(
                spacing: 8,
                children: FilterOption.values.map((option) {
                  final selected = filter == option;
                  final label = "${option.name[0].toUpperCase()}${option.name.substring(1)}";
                  return GestureDetector(
                    onTap: () => onFilterChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? Colors.indigo.shade100 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: selected
                            ? [BoxShadow(
                                color: Colors.indigo.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )]
                            : [],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.indigo.shade800 : Colors.black87,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String title, int value, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          "$value",
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final bool passed;
  final int score;

  const _ResultBadge({required this.passed, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: passed ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            "$score%",
            style: TextStyle(
              color: passed ? Colors.green.shade800 : Colors.orange.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            passed ? "✅ Passed" : "❌ Failed",
            style: TextStyle(
              color: passed ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ Updated QuestionList to handle both formats
class QuestionList extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final Map<String, dynamic> studentAnswers;
  final ScrollController controller;
  final String Function(Map<String, dynamic>, dynamic) getAnswerDisplayText;
  final bool useResultsFormat;

  const QuestionList({
    super.key,
    required this.questions,
    required this.studentAnswers,
    required this.controller,
    required this.getAnswerDisplayText,
    required this.useResultsFormat,
  });

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Center(child: Text("No questions found."));
    }

    return ListView.builder(
      key: ValueKey(questions.hashCode),
      controller: controller,
      physics: const BouncingScrollPhysics(),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final q = questions[index];
        
        // ✅ Get data from results format or legacy format
        bool? isCorrect;
        dynamic studentAnswer;
        dynamic correctAnswer;
        int? pointsAwarded;
        int? maxPoints;
        
        if (useResultsFormat || q.containsKey('isCorrect')) {
          // NEW API format with isCorrect and points
          isCorrect = q['isCorrect'];
          studentAnswer = q['studentAnswer'] ?? studentAnswers[q['id']];
          correctAnswer = q['correctAnswer']; // May be null (hidden by backend)
          pointsAwarded = q['pointsAwarded'];
          maxPoints = q['maxPoints'];
        } else {
          // Legacy format: manual checking
          final answer = studentAnswers[q['id']];
          final correct = q['correct'];
          isCorrect = correct != null &&
              correct.toString().trim().toLowerCase() ==
              answer?.toString().trim().toLowerCase();
          studentAnswer = answer;
          correctAnswer = correct;
          maxPoints = q['marks'];
        }

        // Determine status color and icon
        Color statusColor;
        IconData statusIcon;
        
        if (studentAnswer == null || studentAnswer.toString().isEmpty) {
          statusColor = Colors.grey;
          statusIcon = Icons.help_outline;
        } else if (isCorrect == true) {
          statusColor = Colors.green.shade600;
          statusIcon = Icons.check_circle;
        } else if (isCorrect == false) {
          statusColor = Colors.red.shade600;
          statusIcon = Icons.cancel;
        } else {
          // Manually graded (essay) or null
          statusColor = Colors.orange.shade600;
          statusIcon = Icons.pending;
        }

        // Get display text for answers
        final studentAnswerText = getAnswerDisplayText(q, studentAnswer);
        
        // ✅ Handle hidden correct answers gracefully
        String correctAnswerText;
        if (correctAnswer == null || correctAnswer.toString().isEmpty) {
          correctAnswerText = 'Not available';
        } else {
          correctAnswerText = getAnswerDisplayText(q, correctAnswer);
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: statusColor.withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: ExpansionTile(
            leading: Icon(statusIcon, color: statusColor, size: 28),
            title: Text(
              q['question'] ?? "Question",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isCorrect == true ? Icons.check : Icons.close,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        "Your answer: $studentAnswerText",
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ Show correct answer (or "Not available")
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: correctAnswer == null 
                              ? Colors.grey.shade600 
                              : Colors.green.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Correct answer: $correctAnswerText",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: correctAnswer == null 
                                  ? Colors.grey.shade700 
                                  : Colors.green.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // ✅ Show points if available
                    if (pointsAwarded != null && maxPoints != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.score,
                            color: Colors.blue.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Points: $pointsAwarded / $maxPoints",
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    // Show feedback if available (for essays)
                    if (q.containsKey('feedback') && q['feedback'] != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.feedback,
                              color: Colors.blue.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                q['feedback'],
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}