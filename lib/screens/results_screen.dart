import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pie_chart/pie_chart.dart';
import 'package:confetti/confetti.dart';
import 'student_dashboard.dart';
import '../services/api_service.dart';

// 🧭 Navigation Helper with Fade Transition
void navigateToDashboard(BuildContext context, String studentId, {String? studentName}) {
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      pageBuilder: (_, animation, __) => StudentDashboard(
        studentId: studentId,
        studentName: studentName,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ),
    (route) => false,
  );
}

enum FilterOption { all, correct, incorrect }

class ResultsScreen extends StatefulWidget {
  final String examId;
  final String studentId;
  final String? examTitle;
  final String? subject;

  const ResultsScreen({
    super.key,
    required this.examId,
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
    
    // Load results (tries API first, falls back to local cache)
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

  /// 📥 Load Exam Results (API first, then local cache)
  Future<void> _loadExamResults() async {
    if (_disposed || !mounted) return;

    // Try loading from API first
    bool loadedFromAPI = await _loadExamResultsFromAPI();
    
    if (_disposed || !mounted) return;

    // If API failed, try loading from local cache
    if (!loadedFromAPI) {
      if (kDebugMode) {
        debugPrint('⚠️ API load failed, trying local cache...');
      }
      await _loadExamResultsFromCache();
    }
    
    if (_disposed || !mounted) return;

    if (loaded && questions.isNotEmpty) {
      _animationController.forward();
      _checkAndPlayConfetti();
    }
  }

  /// 🌐 Load results from API
  Future<bool> _loadExamResultsFromAPI() async {
    if (_disposed || !mounted) return false;

    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching results from API for exam: ${widget.examId}');
      }
      
      // Parse examId - try as attempt ID first
      final attemptId = int.tryParse(widget.examId);
      if (attemptId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Invalid exam ID format: ${widget.examId}');
        }
        return false;
      }
      
      final results = await ApiService.fetchExamResults(attemptId: attemptId);
      
      if (_disposed || !mounted) return false;

      if (results != null) {
        if (kDebugMode) {
          debugPrint('✅ Results loaded from API');
          debugPrint('   Questions: ${results['questions']?.length ?? 0}');
          debugPrint('   Answers: ${results['answers']?.length ?? 0}');
        }
        
        setState(() {
          studentAnswers = results['answers'] != null 
              ? Map<String, dynamic>.from(results['answers']) 
              : {};
          questions = results['questions'] != null
              ? List<Map<String, dynamic>>.from(results['questions'])
              : [];
          flagged = results['flagged'] ?? false;
          loaded = true;
          errorMessage = null;
        });
        
        _showSnack("✅ Results loaded successfully!");
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ No results returned from API');
        }
        return false;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ Error loading results from API: $e');
        debugPrint('   Stack: $stackTrace');
      }
      return false;
    }
  }

  /// 💾 Load results from local Hive cache
  Future<void> _loadExamResultsFromCache() async {
    if (_disposed || !mounted) return;

    try {
      final allKeys = examBox.keys.cast<String>();
      final matchingAttempts = allKeys.where((key) {
        final record = examBox.get(key);
        return record is Map &&
            record['recordType'] == 'attempt' &&
            record['attemptId']?.toString().contains(widget.examId) == true &&
            record['attemptId']?.toString().contains(widget.studentId) == true;
      }).toList();

      if (matchingAttempts.isEmpty) {
        if (_disposed || !mounted) return;
        setState(() {
          loaded = true;
          errorMessage = "No results available for this exam.";
        });
        _showSnack("⚠️ No results available for this exam.");
        return;
      }

      final latestAttempt =
          Map<String, dynamic>.from(examBox.get(matchingAttempts.last));

      if (_disposed || !mounted) return;

      setState(() {
        studentAnswers = Map<String, dynamic>.from(
            latestAttempt['answers'] ?? latestAttempt['studentAnswers'] ?? {});
        questions = List<Map<String, dynamic>>.from(latestAttempt['questions'] ?? []);
        flagged = latestAttempt['flagged'] ?? false;
        loaded = true;
        errorMessage = null;
      });
      
      if (kDebugMode) {
        debugPrint('✅ Results loaded from cache');
      }
      _showSnack("✅ Results loaded from cache");
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ Error loading from cache: $e');
        debugPrint('   Stack: $stackTrace');
      }
      if (_disposed || !mounted) return;
      setState(() {
        loaded = true;
        errorMessage = "Failed to load results from cache.";
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

  // 🧮 Computations
  int getCorrectCount() => questions.where((q) {
        final correct = q['correct']?.toString().trim().toLowerCase();
        final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
        return correct == answer;
      }).length;

  int getIncorrectCount() => questions.length - getCorrectCount();

  int getUnansweredCount() => questions.length -
      studentAnswers.entries
          .where((e) => e.value != null && e.value.toString().isNotEmpty)
          .length;

  List<Map<String, dynamic>> getFilteredQuestions() {
    switch (filter) {
      case FilterOption.correct:
        return questions.where((q) {
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct == answer;
        }).toList();
      case FilterOption.incorrect:
        return questions.where((q) {
          final correct = q['correct']?.toString().trim().toLowerCase();
          final answer = studentAnswers[q['id']]?.toString().trim().toLowerCase();
          return correct != answer;
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

    // Show error state if no questions
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.examTitle ?? "Exam Results"),
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 20),
              Text(
                errorMessage ?? 'No results available.',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
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
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          navigateToDashboard(context, widget.studentId),
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

// 📊 Exam Summary Card Widget
class ExamSummaryCard extends StatelessWidget {
  final int correctCount, incorrectCount, unansweredCount, total, scorePercent;
  final bool passed, flagged;
  final Map<String, double> dataMap;
  final FilterOption filter;
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
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
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
                chartValuesOptions:
                    const ChartValuesOptions(showChartValuesInPercentage: true),
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
                  final label =
                      "${option.name[0].toUpperCase()}${option.name.substring(1)}";
                  return GestureDetector(
                    onTap: () => onFilterChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.indigo.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.indigo.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : [],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? Colors.indigo.shade800
                              : Colors.black87,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
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

// 🧾 Question List
class QuestionList extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final Map<String, dynamic> studentAnswers;
  final ScrollController controller;

  const QuestionList({
    super.key,
    required this.questions,
    required this.studentAnswers,
    required this.controller,
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
        final isCorrect =
            correct?.toString().trim().toLowerCase() ==
            answer?.toString().trim().toLowerCase();

        final Color statusColor = (answer == null || answer.toString().isEmpty)
            ? Colors.grey
            : (isCorrect ? Colors.green.shade600 : Colors.red.shade600);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: statusColor.withOpacity(0.4)),
          ),
          child: ExpansionTile(
            leading: Icon(
              (answer == null || answer.toString().isEmpty)
                  ? Icons.access_time
                  : (isCorrect ? Icons.check_circle : Icons.cancel),
              color: statusColor,
            ),
            title: Text(q['question'] ?? "Question",
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              (answer == null || answer.toString().isEmpty)
                  ? "No answer"
                  : "Your answer: $answer",
              style: TextStyle(color: statusColor),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "Correct answer: ${q['correct'] ?? 'N/A'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}