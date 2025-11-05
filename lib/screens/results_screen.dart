import 'dart:convert';
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
  final String attemptId;  // ✅ This is now correct - attempt ID
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
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
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

    // If API failed or returned no questions, try cache
    if (!loadedFromAPI || questions.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ API load incomplete, trying local cache...');
      }
      await _loadExamResultsFromCache();
    }
    
    if (_disposed || !mounted) return;

    if (loaded && questions.isNotEmpty) {
      _animationController.forward();
      _checkAndPlayConfetti();
    }
  }

  Future<bool> _loadExamResultsFromAPI() async {
    if (_disposed || !mounted) return false;

    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching results from API for attempt: ${widget.attemptId}');
        debugPrint('   Student ID: ${widget.studentId}');
      }
      
      final attemptId = int.tryParse(widget.attemptId);
      if (attemptId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Invalid attempt ID format: ${widget.attemptId}');
        }
        return false;
      }
      
      final results = await ApiService.fetchExamResults(attemptId: attemptId);
      
      if (_disposed || !mounted) return false;

      if (results != null && results['error'] == null) {
        if (kDebugMode) {
          debugPrint('✅ API Response received');
          debugPrint('   Response keys: ${results.keys.toList()}');
        }
        
        // ✅ Extract score and total marks from attempt data
        if (results['attempt'] != null) {
          score = results['attempt']['score'];
          totalMarks = results['attempt']['total_marks'];
          if (kDebugMode) {
            debugPrint('   Score: $score / $totalMarks');
          }
        }
        
        // Handle different API response formats
        final questionsData = results['questions'] ?? 
                             results['results']?['questions'] ??
                             results['attempt']?['questions'] ?? 
                             results['exam']?['questions'] ?? [];
        
        final answersData = results['answers'] ?? 
                           results['results']?['answers'] ??
                           results['attempt']?['answers'] ?? 
                           results['studentAnswers'] ?? {};
        
        if (kDebugMode) {
          debugPrint('   Questions found: ${questionsData is List ? questionsData.length : 0}');
          debugPrint('   Answers found: ${answersData is Map ? answersData.length : 0}');
        }

        // ✅ If API doesn't return questions/answers, we'll use cache
        if ((questionsData is! List || questionsData.isEmpty) && 
            (answersData is! Map || answersData.isEmpty)) {
          if (kDebugMode) {
            debugPrint('⚠️ API returned no questions/answers, will use cache');
          }
          
          // But keep the score from API
          if (mounted) {
            setState(() {
              loaded = true;
            });
          }
          return false; // Signal to load from cache
        }
        
        // Process questions
        final processedQuestions = <Map<String, dynamic>>[];
        if (questionsData is List) {
          for (var q in questionsData) {
            if (q is Map) {
              final questionMap = Map<String, dynamic>.from(q);
              
              // Ensure ID field exists
              if (questionMap['id'] == null) {
                questionMap['id'] = questionMap['item_id']?.toString() ?? 
                                   questionMap['question_id']?.toString() ?? 
                                   'item_${processedQuestions.length}';
              }
              
              // Map correct answer from multiple possible field names
              if (questionMap['correct'] == null) {
                questionMap['correct'] = questionMap['correct_answer'] ?? 
                                        questionMap['answer'] ?? 
                                        questionMap['correctAnswer'] ??
                                        questionMap['correct_key'] ??
                                        questionMap['answer_key'];
              }
              
              // Convert choice keys to text for MCQ
              if ((questionMap['type'] == 'mcq' || questionMap['type'] == 'true_false') && 
                  questionMap['choices'] != null) {
                final choices = questionMap['choices'];
                if (choices is List && questionMap['correct'] != null) {
                  final correctKey = questionMap['correct'].toString();
                  final correctChoice = choices.firstWhere(
                    (c) => c['key']?.toString().toLowerCase() == correctKey.toLowerCase(),
                    orElse: () => null,
                  );
                  
                  if (correctChoice != null) {
                    questionMap['correct_text'] = correctChoice['text'];
                  }
                }
              }
              
              processedQuestions.add(questionMap);
            }
          }
        }
        
        // Process answers
        final processedAnswers = <String, dynamic>{};
        if (answersData is Map) {
          answersData.forEach((key, value) {
            processedAnswers[key.toString()] = value;
          });
        }
        
        if (mounted) {
          setState(() {
            studentAnswers = processedAnswers;
            questions = processedQuestions;
            flagged = results['flagged'] ?? results['attempt']?['flagged'] ?? false;
            loaded = true;
            errorMessage = null;
          });
        }
        
        if (kDebugMode) {
          debugPrint('✅ Loaded ${questions.length} questions, ${studentAnswers.length} answers from API');
        }
        
        if (mounted && questions.isNotEmpty) {
          _showSnack("✅ Results loaded from server!");
        }
        return questions.isNotEmpty;
      } else {
        final errorMsg = results?['error'] ?? 'No results available';
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
    
    // ✅ NEW Strategy: Search all exam records for matching attemptId
    for (var key in allKeys) {
      final record = examBox.get(key);
      if (record is! Map) continue;
      
      // Match by attemptId in the record
      final recordAttemptId = record['attemptId']?.toString() ?? 
                             record['attempt']?['attempt_id']?.toString();
      
      if (recordAttemptId == widget.attemptId && 
          record['studentId'] == widget.studentId &&
          record['submitted'] == true) {
        matchingKey = key;
        if (kDebugMode) {
          debugPrint('   ✓ Found matching record: $key');
          debugPrint('   Attempt ID in record: $recordAttemptId');
        }
        break;
      }
    }

    if (matchingKey == null) {
      if (kDebugMode) {
        debugPrint('⚠️ No matching cached results found');
        
        // Debug: Show what we have
        final relevantKeys = allKeys
            .where((k) => k.contains(widget.studentId))
            .toList();
        debugPrint('   Keys for this student: ${relevantKeys.take(3).join(", ")}');
        
        // Show attempt IDs we found
        for (var key in relevantKeys.take(3)) {
          final rec = examBox.get(key);
          if (rec is Map) {
            final aid = rec['attemptId']?.toString() ?? 
                       rec['attempt']?['attempt_id']?.toString() ?? 'none';
            debugPrint('   $key -> attemptId: $aid');
          }
        }
      }
      
      if (_disposed || !mounted) return;
      setState(() {
        loaded = true;
        errorMessage = errorMessage ?? 
            "Results not available offline. Please check your connection and try again.";
      });
      return;
    }

    // ✅ Load from matched cache
    final cachedRecord = Map<String, dynamic>.from(examBox.get(matchingKey));
    
    if (kDebugMode) {
      debugPrint('✅ Using cached record from: $matchingKey');
    }

    if (_disposed || !mounted) return;

    setState(() {
      // Extract answers - could be in multiple locations
      final rawAnswers = cachedRecord['answers'] ?? 
                        cachedRecord['studentAnswers'] ?? 
                        cachedRecord['attempt']?['answers'] ?? {};
      studentAnswers = Map<String, dynamic>.from(rawAnswers);
      
      // Extract questions
      final rawQuestions = cachedRecord['questions'] ?? 
                          cachedRecord['attempt']?['questions'] ?? [];
      questions = (rawQuestions as List)
          .map((q) => Map<String, dynamic>.from(q))
          .toList();
      
      // Extract score
      score = cachedRecord['score'] ?? 
             cachedRecord['attempt']?['score'];
      totalMarks = cachedRecord['totalMarks'] ?? 
                  cachedRecord['total_marks'] ??
                  cachedRecord['attempt']?['total_marks'];
      
      flagged = cachedRecord['flagged'] ?? false;
      loaded = true;
      errorMessage = null;
    });
    
    if (kDebugMode) {
      debugPrint('✅ Loaded from cache:');
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
    final total = questions.length;
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

  // Helper to get display text for answers
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

  int getCorrectCount() => questions.where((q) {
        final correct = q['correct']?.toString().trim().toLowerCase();
        final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
        return correct != null && correct == answer && correct != 'n/a' && correct.isNotEmpty;
      }).length;

  int getIncorrectCount() => questions.where((q) {
        final correct = q['correct']?.toString().trim().toLowerCase();
        final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
        return correct != null && correct != answer && correct != 'n/a' && 
               correct.isNotEmpty && answer != null && answer.isNotEmpty;
      }).length;

  int getUnansweredCount() => questions.where((q) {
        final answer = studentAnswers[q['id']];
        return answer == null || answer.toString().isEmpty;
      }).length;

  List<Map<String, dynamic>> getFilteredQuestions() {
    switch (filter) {
      case FilterOption.correct:
        return questions.where((q) {
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct != null && correct == answer && correct != 'n/a';
        }).toList();
      case FilterOption.incorrect:
        return questions.where((q) {
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct != null && correct != answer && correct != 'n/a';
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

    if (questions.isEmpty) {
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

    final correctCount = getCorrectCount();
    final incorrectCount = getIncorrectCount();
    final unansweredCount = getUnansweredCount();
    final total = questions.length;
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
            Container(
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
                      questions: getFilteredQuestions(),
                      studentAnswers: studentAnswers,
                      controller: _scrollController,
                      getAnswerDisplayText: getAnswerDisplayText,
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
                chartValuesOptions: const ChartValuesOptions(showChartValuesInPercentage: true),
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
                            ? [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]
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
        Text("$value", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
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

  const QuestionList({
    super.key,
    required this.questions,
    required this.studentAnswers,
    required this.controller,
    required this.getAnswerDisplayText,
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
        final answer = studentAnswers[q['id']];
        final correct = q['correct'];
        
        final isCorrect = correct != null &&
            correct.toString().trim().toLowerCase() ==
            answer?.toString().trim().toLowerCase();

        final Color statusColor = (answer == null || answer.toString().isEmpty)
            ? Colors.grey
            : (isCorrect ? Colors.green.shade600 : Colors.red.shade600);

        final studentAnswerText = getAnswerDisplayText(q, answer);
        final correctAnswerText = correct != null ? getAnswerDisplayText(q, correct) : 'Not available';

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: statusColor.withOpacity(0.4), width: 1.5),
          ),
          child: ExpansionTile(
            leading: Icon(
              (answer == null || answer.toString().isEmpty)
                  ? Icons.help_outline
                  : (isCorrect ? Icons.check_circle : Icons.cancel),
              color: statusColor,
              size: 28,
            ),
            title: Text(
              q['question'] ?? "Question",
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(isCorrect ? Icons.check : Icons.close, size: 16, color: statusColor),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
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
              ),
            ],
          ),
        );
      },
    );
  }
}