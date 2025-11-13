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

enum FilterOption { all, correct, incorrect, pending }

class ResultsScreen extends StatefulWidget {
  final String attemptId;
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

  List<Map<String, dynamic>> results = [];
  Map<String, dynamic>? statistics;
  Map<String, dynamic>? attemptInfo;
  
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
  int pendingGradingCount = 0;

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

    bool loadedFromAPI = await _loadExamResultsFromAPI();
    
    if (_disposed || !mounted) return;

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
        
        if (apiResponse['statistics'] != null) {
          statistics = Map<String, dynamic>.from(apiResponse['statistics']);
          
          correctCount = (statistics!['correctAnswers'] as num?)?.toInt() ?? 0;
          incorrectCount = (statistics!['incorrectAnswers'] as num?)?.toInt() ?? 0;
          unansweredCount = (statistics!['unanswered'] as num?)?.toInt() ?? 0;
          pendingGradingCount = (statistics!['pendingGrading'] as num?)?.toInt() ?? 0;

          if (kDebugMode) {
            debugPrint('   📈 Statistics:');
            debugPrint('      Correct: $correctCount');
            debugPrint('      Incorrect: $incorrectCount');
            debugPrint('      Unanswered: $unansweredCount');
            debugPrint('      Pending: $pendingGradingCount');
          }
        }
        
        if (apiResponse['results'] != null && apiResponse['results'] is List) {
          results = List<Map<String, dynamic>>.from(apiResponse['results']);
          
          if (kDebugMode) {
            debugPrint('   ✅ Results array found: ${results.length} items');
            if (results.isNotEmpty) {
              final sample = results[0];
              debugPrint('   Sample result keys: ${sample.keys.toList()}');
            }
          }
          
          questions = results.map((r) => {
            'id': r['id'],
            'itemId': r['itemId'],
            'question': r['question'],
            'type': r['type'],
            'choices': r['choices'],
            'correct': r['correctAnswer'],
            'marks': r['maxPoints'],
            'isCorrect': r['isCorrect'],
            'pointsAwarded': r['pointsAwarded'],
            'maxPoints': r['maxPoints'],
            'feedback': r['feedback'],
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
        } else {
          if (kDebugMode) {
            debugPrint('   ⚠️ No results array, trying legacy format...');
          }
          
          if (apiResponse['questions'] != null && apiResponse['questions'] is List) {
            questions = List<Map<String, dynamic>>.from(apiResponse['questions']);
          }
          
          if (apiResponse['answers'] != null && apiResponse['answers'] is Map) {
            studentAnswers = Map<String, dynamic>.from(apiResponse['answers']);
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
      }
      
      final allKeys = examBox.keys.cast<String>().toList();
      String? matchingKey;
      
      for (var key in allKeys) {
        final record = examBox.get(key);
        if (record is! Map) continue;
        
        final recordAttemptId = record['attemptId']?.toString() ?? 
                               record['attempt']?['attempt_id']?.toString();
        
        if (recordAttemptId == widget.attemptId && 
            record['studentId'] == widget.studentId) {
          matchingKey = key;
          break;
        }
      }

      if (matchingKey == null) {
        if (_disposed || !mounted) return;
        setState(() {
          loaded = true;
          errorMessage = errorMessage ?? 
              "Results not available offline. Please check your connection.";
        });
        return;
      }

      final cachedRecord = Map<String, dynamic>.from(examBox.get(matchingKey));

      if (_disposed || !mounted) return;

      setState(() {
        if (cachedRecord['results'] != null && cachedRecord['results'] is List) {
          results = List<Map<String, dynamic>>.from(cachedRecord['results']);
        }
        
        final rawAnswers = cachedRecord['answers'] ?? 
                          cachedRecord['studentAnswers'] ?? {};
        studentAnswers = Map<String, dynamic>.from(rawAnswers);
        
        final rawQuestions = cachedRecord['questions'] ?? [];
        questions = (rawQuestions as List)
            .map((q) => Map<String, dynamic>.from(q))
            .toList();
        
        score = cachedRecord['score'] ?? cachedRecord['attempt']?['score'];
        totalMarks = cachedRecord['totalMarks'] ?? 
                    cachedRecord['total_marks'] ??
                    cachedRecord['attempt']?['total_marks'];
        
        if (cachedRecord['statistics'] != null) {
          statistics = Map<String, dynamic>.from(cachedRecord['statistics']);
          correctCount = (statistics!['correctAnswers'] as num?)?.toInt() ?? 0;
          incorrectCount = (statistics!['incorrectAnswers'] as num?)?.toInt() ?? 0;
          unansweredCount = (statistics!['unanswered'] as num?)?.toInt() ?? 0;
          pendingGradingCount = (statistics!['pendingGrading'] as num?)?.toInt() ?? 0;
        }
        
        flagged = cachedRecord['flagged'] ?? false;
        loaded = true;
        errorMessage = null;
      });
      
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

    final scorePercent = getScorePercent();

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

  String getAnswerDisplayText(Map<String, dynamic> question, dynamic answerValue) {
    if (answerValue == null || answerValue.toString().isEmpty) {
      return "No answer provided";
    }

    final answerStr = answerValue.toString();
    
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
    if (results.isNotEmpty) return results.length;
    if (questions.isNotEmpty) return questions.length;
    
    if (statistics != null && statistics!['totalQuestions'] != null) {
      return (statistics!['totalQuestions'] as num?)?.toInt() ?? 0;
    }
    
    return 0;
  }

  int getCorrectCount() {
    if (statistics != null && statistics!['correctAnswers'] != null) {
      return (statistics!['correctAnswers'] as num?)?.toInt() ?? 0;
    }
    
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

  int getPointsEarned() {
    if (score != null) return score!;
    
    if (results.isNotEmpty) {
      return results.fold<int>(0, (sum, r) {
        final points = (r['pointsAwarded'] as num?)?.toInt() ?? 0;
        return sum + points;
      });
    }
    
    return getCorrectCount();
  }

  int getTotalPossiblePoints() {
    if (totalMarks != null) return totalMarks!;
    
    if (results.isNotEmpty) {
      return results.fold<int>(0, (sum, r) {
        final maxPoints = (r['maxPoints'] as num?)?.toInt() ?? 1;
        return sum + maxPoints;
      });
    }
    
    if (questions.isNotEmpty) {
      return questions.fold<int>(0, (sum, q) {
        final marks = (q['marks'] as num?)?.toInt() ?? 1;
        return sum + marks;
      });
    }
    
    return getTotalQuestions();
  }

  int getScorePercent() {
    final pointsEarned = getPointsEarned();
    final totalPoints = getTotalPossiblePoints();
    
    if (totalPoints == 0) return 0;
    
    return ((pointsEarned / totalPoints) * 100).round();
  }

  int getIncorrectCount() {
    if (statistics != null && statistics!['incorrectAnswers'] != null) {
      return (statistics!['incorrectAnswers'] as num?)?.toInt() ?? 0;
    }
    
    if (results.isNotEmpty) {
      return results.where((r) {
        final hasAnswer = r['studentAnswer'] != null && 
                         r['studentAnswer'].toString().isNotEmpty;
        return hasAnswer && r['isCorrect'] == false;
      }).length;
    }
    
    if (questions.isNotEmpty) {
      return questions.where((q) {
        final answer = studentAnswers[q['id']];
        final hasAnswer = answer != null && answer.toString().isNotEmpty;
        
        if (!hasAnswer) return false;
        
        if (q['isCorrect'] != null) {
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
    if (statistics != null && statistics!['unanswered'] != null) {
      return (statistics!['unanswered'] as num?)?.toInt() ?? 0;
    }
    
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

  int getPendingGradingCount() {
    if (statistics != null && statistics!['pendingGrading'] != null) {
      return (statistics!['pendingGrading'] as num?)?.toInt() ?? 0;
    }
    
    if (results.isNotEmpty) {
      return results.where((r) {
        final hasAnswer = r['studentAnswer'] != null && 
                         r['studentAnswer'].toString().isNotEmpty;
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
    if (results.isNotEmpty) {
      switch (filter) {
        case FilterOption.correct:
          return results.where((r) => r['isCorrect'] == true).toList();
        case FilterOption.incorrect:
          return results.where((r) => r['isCorrect'] == false).toList();
        case FilterOption.pending:
          return results.where((r) {
            final hasAnswer = r['studentAnswer'] != null && 
                             r['studentAnswer'].toString().isNotEmpty;
            return hasAnswer && r['isCorrect'] == null;
          }).toList();
        case FilterOption.all:
        default:
          return results;
      }
    }
    
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
      case FilterOption.pending:
        return questions.where((q) {
          final answer = studentAnswers[q['id']];
          final hasAnswer = answer != null && answer.toString().isNotEmpty;
          return hasAnswer && q['isCorrect'] == null;
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
    final pendingCount = getPendingGradingCount();
    final total = getTotalQuestions();
    final scorePercent = getScorePercent();
    final pointsEarned = getPointsEarned();
    final totalPoints = getTotalPossiblePoints();
    final passed = scorePercent >= 75;

    final dataMap = {
      "Correct": correctCount.toDouble(),
      "Incorrect": incorrectCount.toDouble(),
      "Unanswered": unansweredCount.toDouble(),
      if (pendingCount > 0) "Pending": pendingCount.toDouble(),
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
                          pendingCount: pendingCount,
                          total: total,
                          scorePercent: scorePercent,
                          passed: passed,
                          flagged: flagged,
                          dataMap: dataMap,
                          filter: filter,
                          score: score,
                          totalMarks: totalMarks,
                          pointsEarned: pointsEarned,
                          totalPoints: totalPoints,
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

class ExamSummaryCard extends StatelessWidget {
  final int correctCount, incorrectCount, unansweredCount, pendingCount, total, scorePercent;
  final bool passed, flagged;
  final Map<String, double> dataMap;
  final FilterOption filter;
  final int? score;
  final int? totalMarks;
  final int? pointsEarned;
  final int? totalPoints;
  final ValueChanged<FilterOption> onFilterChanged;

  const ExamSummaryCard({
    super.key,
    required this.correctCount,
    required this.incorrectCount,
    required this.unansweredCount,
    required this.pendingCount,
    required this.total,
    required this.scorePercent,
    required this.passed,
    required this.flagged,
    required this.dataMap,
    required this.filter,
    this.score,
    this.totalMarks,
    this.pointsEarned,
    this.totalPoints,
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
            
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  if (score != null && totalMarks != null)
                    Text(
                      'Score: $score / $totalMarks',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  if (pointsEarned != null && totalPoints != null && 
                      (score != pointsEarned || totalMarks != totalPoints))
                    Text(
                      'Points: $pointsEarned / $totalPoints',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade500,
                      ),
                    ),
                ],
              ),
            ),
            
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
                if (pendingCount > 0)
                  _buildStat("Pending", pendingCount, Colors.orange),
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
                  Colors.grey.shade400,
                  if (pendingCount > 0) Colors.orange.shade400,
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
                  
                  if (option == FilterOption.pending && pendingCount == 0) {
                    return const SizedBox.shrink();
                  }
                  
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
        Text(title, style: const TextStyle(fontSize: 12)),
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
        
        bool? isCorrect;
        dynamic studentAnswer;
        dynamic correctAnswer;
        int? pointsAwarded;
        int? maxPoints;
        String? feedback;
        
        if (useResultsFormat || q.containsKey('feedback')) {
          isCorrect = q['isCorrect'];
          studentAnswer = q['studentAnswer'] ?? studentAnswers[q['id']];
          correctAnswer = q['correctAnswer'];
          pointsAwarded = (q['pointsAwarded'] as num?)?.toInt();
          maxPoints = (q['maxPoints'] as num?)?.toInt();
          feedback = q['feedback'];
        } else {
          final answer = studentAnswers[q['id']];
          final correct = q['correct'];
          isCorrect = correct != null &&
              correct.toString().trim().toLowerCase() ==
              answer?.toString().trim().toLowerCase();
          studentAnswer = answer;
          correctAnswer = correct;
          maxPoints = (q['marks'] as num?)?.toInt();
        }

        final questionType = q['type']?.toString().toLowerCase() ?? '';
        final isEssay = questionType == 'essay';
        
        final hasAnswer = studentAnswer != null && studentAnswer.toString().isNotEmpty;

        Color statusColor;
        IconData statusIcon;
        String statusText;
        
        if (!hasAnswer) {
          statusColor = Colors.grey.shade600;
          statusIcon = Icons.help_outline;
          statusText = "Unanswered";
        } else if (isEssay) {
          if (pointsAwarded != null && feedback != null && feedback.isNotEmpty) {
            statusColor = Colors.blue.shade700;
            statusIcon = Icons.verified;
            statusText = "AI Graded";
          } else if (pointsAwarded != null) {
            statusColor = Colors.green.shade600;
            statusIcon = Icons.check_circle;
            statusText = "Graded";
          } else {
            statusColor = Colors.orange.shade600;
            statusIcon = Icons.pending;
            statusText = "Pending Grading";
          }
        } else if (isCorrect == true) {
          statusColor = Colors.green.shade600;
          statusIcon = Icons.check_circle;
          statusText = "Correct";
        } else if (isCorrect == false) {
          statusColor = Colors.red.shade600;
          statusIcon = Icons.cancel;
          statusText = "Incorrect";
        } else {
          statusColor = Colors.orange.shade600;
          statusIcon = Icons.pending;
          statusText = "Pending";
        }

        final studentAnswerText = getAnswerDisplayText(q, studentAnswer);
        
        String? correctAnswerText;
        if (!isEssay && correctAnswer != null && correctAnswer.toString().isNotEmpty) {
          correctAnswerText = getAnswerDisplayText(q, correctAnswer);
        }

        final hasFeedback = feedback != null && feedback.isNotEmpty;

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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (pointsAwarded != null && maxPoints != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        "$pointsAwarded/$maxPoints pts",
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isEssay ? Icons.article_outlined : Icons.edit_outlined,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isEssay && studentAnswerText.length > 60
                            ? "${studentAnswerText.substring(0, 60)}..."
                            : studentAnswerText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (isEssay && hasFeedback) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "AI Feedback available",
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isEssay) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.edit_note,
                                  size: 18,
                                  color: Colors.grey.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Your Essay Answer:",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: SingleChildScrollView(
                                child: Text(
                                  studentAnswerText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade800,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    
                    if (!isEssay && correctAnswerText != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Correct answer: $correctAnswerText",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    
                    if (pointsAwarded != null && maxPoints != null && !isEssay) ...[
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
                      const SizedBox(height: 8),
                    ],
                    
                    if (isEssay && hasFeedback) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade50,
                              Colors.indigo.shade50,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1.5,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.auto_awesome,
                                      color: Colors.blue.shade700,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "AI Feedback",
                                      style: TextStyle(
                                        color: Colors.blue.shade900,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                feedback!,
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (isEssay && pointsAwarded != null && !hasFeedback) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Graded by instructor - No AI feedback provided",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
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