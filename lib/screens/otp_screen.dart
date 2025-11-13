import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'results_screen.dart';
import 'exam_screen.dart';
import '../services/api_service.dart';

class OTPScreen extends StatefulWidget {
  final String examId;
  final String subject;
  final String? expectedOTP;
  final bool forResults;
  final String studentId;
  final VoidCallback? onVerified;
  final String? attemptId;
  
  // Exam details for enhanced display
  final String? examTitle;
  final String? examDate;
  final String? examTime;
  final String? duration;
  final int? questionCount;

  const OTPScreen({
    super.key,
    required this.examId,
    required this.subject,
    this.expectedOTP,
    this.forResults = false,
    required this.studentId,
    this.onVerified,
    this.attemptId,
    this.examTitle,
    this.examDate,
    this.examTime,
    this.duration,
    this.questionCount,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen>
    with TickerProviderStateMixin {
  final TextEditingController passwordController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _obscurePassword = true;
  bool _isVerifying = false;
  bool _isError = false;
  bool _isSuccess = false;
  bool _disposed = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _successController;
  
  PasswordStrength _passwordStrength = PasswordStrength.none;

  @override
  void initState() {
    super.initState();
    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_pulseController);
    
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) {
        _focusNode.requestFocus();
      }
    });
    
    passwordController.addListener(_updatePasswordStrength);
  }

  void _updatePasswordStrength() {
    final password = passwordController.text;
    final length = password.length;
    
    if (!mounted) return;
    
    setState(() {
      if (length == 0) {
        _passwordStrength = PasswordStrength.none;
      } else if (length < 4) {
        _passwordStrength = PasswordStrength.weak;
      } else if (length < 6) {
        _passwordStrength = PasswordStrength.medium;
      } else {
        _passwordStrength = PasswordStrength.strong;
      }
    });
  }

  // ✅ NEW: Helper method to format date and time
  Map<String, String?> _parseExamDateTime() {
    String? formattedDate;
    String? formattedTime;
    
    if (widget.examDate != null) {
      try {
        // Try parsing ISO format
        final parsedDate = DateTime.parse(widget.examDate!);
        formattedDate = DateFormat('MMM dd, yyyy').format(parsedDate);
        
        // If no separate time is provided, extract from date
        if (widget.examTime == null) {
          formattedTime = DateFormat('h:mm a').format(parsedDate);
        }
      } catch (e) {
        // If parsing fails, use original
        formattedDate = widget.examDate;
      }
    }
    
    // Use provided time if available
    if (widget.examTime != null) {
      formattedTime = widget.examTime;
    }
    
    return {
      'date': formattedDate,
      'time': formattedTime,
    };
  }

  Future<void> _verifyPassword() async {
    if (_disposed || !mounted) return;

    final enteredPassword = passwordController.text.trim();

    if (enteredPassword.isEmpty) {
      if (!mounted) return;
      setState(() => _isError = true);
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      
      _showFloatingMessage(
        message: "Please enter the exam password",
        success: false,
      );
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _isError = false);
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isVerifying = true;
      _isError = false;
      _isSuccess = false;
    });

    int examIdInt;
    int studentIdInt;
    
    try {
      examIdInt = int.parse(widget.examId);
      if (kDebugMode) {
        debugPrint('✅ Parsed exam ID: $examIdInt');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to parse exam ID "${widget.examId}": $e');
      }
      if (!mounted) return;
      setState(() {
        _isError = true;
        _isVerifying = false;
      });
      _showFloatingMessage(
        message: "Invalid exam ID: ${widget.examId}",
        success: false,
      );
      return;
    }
    
    try {
      studentIdInt = int.parse(widget.studentId);
      if (kDebugMode) {
        debugPrint('✅ Parsed student ID: $studentIdInt');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to parse student ID "${widget.studentId}": $e');
      }
      if (!mounted) return;
      setState(() {
        _isError = true;
        _isVerifying = false;
      });
      _showFloatingMessage(
        message: "Invalid student ID: ${widget.studentId}",
        success: false,
      );
      return;
    }

    if (kDebugMode) {
      debugPrint('🔐 Verifying password for exam $examIdInt with API...');
    }

    final verified = await ApiService.verifyExamPassword(
      examId: examIdInt,
      studentId: studentIdInt,
      password: enteredPassword,
    );

    if (_disposed || !mounted) return;

    if (verified) {
      if (kDebugMode) {
        debugPrint('✅ Password verified successfully');
      }
      HapticFeedback.lightImpact();
      
      setState(() {
        _isSuccess = true;
        _isVerifying = false;
      });
      
      _successController.forward();
      
      _showFloatingMessage(
        message: widget.forResults
            ? "Password Verified! Loading Results..."
            : "Password Verified! Starting Exam...",
        success: true,
      );

      await Future.delayed(const Duration(milliseconds: 1200));

      if (_disposed || !mounted) return;

      if (widget.forResults) {
        if (widget.attemptId == null || widget.attemptId!.isEmpty) {
          if (kDebugMode) {
            debugPrint('⚠️ WARNING: No attempt ID provided for results screen!');
          }
          
          _showFloatingMessage(
            message: "Cannot load results: Missing attempt information",
            success: false,
          );
          
          if (mounted && !_disposed) {
            setState(() {
              _isVerifying = false;
              _isSuccess = false;
            });
          }
          return;
        }
        
        if (kDebugMode) {
          debugPrint('📊 Navigating to results screen');
        }
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultsScreen(
              attemptId: widget.attemptId!,
              studentId: widget.studentId,
              examTitle: widget.examTitle ?? widget.subject,
            ),
          ),
        );
      } else {
        if (kDebugMode) {
          debugPrint('📝 Starting exam');
        }
        
        if (widget.onVerified != null) {
          widget.onVerified!();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ExamScreen(
                studentId: widget.studentId,
                subject: widget.subject,
                examId: widget.examId,
              ),
            ),
          );
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('❌ Password verification failed');
      }
      HapticFeedback.heavyImpact();
      
      if (!mounted) return;
      setState(() {
        _isError = true;
        _isVerifying = false;
        _isSuccess = false;
      });
      _shakeController.forward(from: 0);
      
      _showFloatingMessage(
        message: "Incorrect password. Please try again.",
        success: false,
      );
      
      passwordController.clear();
      _focusNode.requestFocus();
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _isError = false);
      });
    }

    if (mounted && !_disposed) {
      setState(() => _isVerifying = false);
    }
  }

  void _showFloatingMessage({required String message, required bool success}) {
    if (_disposed || !mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFF44336),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    passwordController.removeListener(_updatePasswordStrength);
    passwordController.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.forResults
        ? "View Your Results"
        : "Exam Authentication";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLockIcon(),
                      const SizedBox(height: 20),
                      
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.examTitle ?? widget.subject,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF3B82F6),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      if (!widget.forResults) ...[
                        const SizedBox(height: 20),
                        _buildExamDetailsCard(),
                      ],
                      
                      const SizedBox(height: 24),
                      _buildInfoBox(),
                      const SizedBox(height: 20),

                      AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_isError ? _shakeAnimation.value : 0, 0),
                            child: child,
                          );
                        },
                        child: _buildPasswordInput(),
                      ),

                      if (_passwordStrength != PasswordStrength.none)
                        _buildStrengthIndicator(),

                      const SizedBox(height: 24),
                      
                      if (_isVerifying) _buildVerifyingStatus(),
                      
                      _buildVerifyButton(),
                      
                      const SizedBox(height: 12),
                      
                      _buildBackButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _buildHelpButton(),
    );
  }

  Widget _buildLockIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.2),
                  const Color(0xFF3B82F6).withOpacity(0.1),
                ],
              ),
            ),
          ),
        ),
        
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _isSuccess
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 40,
                    color: Color(0xFF10B981),
                    key: ValueKey('success'),
                  )
                : Icon(
                    Icons.lock_rounded,
                    size: 36,
                    color: const Color(0xFF3B82F6),
                    key: const ValueKey('lock'),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildExamDetailsCard() {
    final dateTime = _parseExamDateTime();
    final formattedDate = dateTime['date'];
    final formattedTime = dateTime['time'];
    
    // Debug logging
    if (kDebugMode) {
      debugPrint('🎨 Building exam details card:');
      debugPrint('   Date: $formattedDate');
      debugPrint('   Time: $formattedTime');
      debugPrint('   Duration: ${widget.duration}');
      debugPrint('   Question Count: ${widget.questionCount}');
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          if (formattedDate != null)
            _buildDetailRow(
              Icons.calendar_today_rounded,
              formattedDate,
              const Color(0xFF3B82F6),
            ),
          if (formattedTime != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.access_time_rounded,
              formattedTime,
              const Color(0xFF8B5CF6),
            ),
          ],
          if (widget.duration != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.timer_rounded,
              '${widget.duration} ${widget.duration == '1' ? 'hour' : 'hours'}',
              const Color(0xFF10B981),
            ),
          ],
          if (widget.questionCount != null && widget.questionCount! > 0) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.quiz_rounded,
              '${widget.questionCount} question${widget.questionCount! > 1 ? 's' : ''}',
              const Color(0xFFF59E0B),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_rounded,
            color: Color(0xFF3B82F6),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.forResults
                  ? "Enter the password to view your results"
                  : "Enter the password to start your exam",
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput() {
    return TextField(
      controller: passwordController,
      focusNode: _focusNode,
      obscureText: _obscurePassword,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 18,
        letterSpacing: _obscurePassword ? 6.0 : 1.0,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade800,
      ),
      decoration: InputDecoration(
        hintText: "Enter password",
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 15,
          letterSpacing: 1.0,
        ),
        prefixIcon: Icon(
          Icons.key_rounded,
          size: 20,
          color: _isError
              ? const Color(0xFFF44336)
              : _isSuccess
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6B7280),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 20,
            color: Colors.grey.shade600,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        filled: true,
        fillColor: _isError
            ? const Color(0xFFF44336).withOpacity(0.05)
            : _isSuccess
                ? const Color(0xFF10B981).withOpacity(0.05)
                : Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _isError
                ? const Color(0xFFF44336)
                : _isSuccess
                    ? const Color(0xFF10B981)
                    : const Color(0xFF3B82F6),
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _isError
                ? const Color(0xFFF44336).withOpacity(0.5)
                : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _verifyPassword(),
      enabled: !_isVerifying,
    );
  }

  Widget _buildStrengthIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: _getStrengthBarColor(index),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _passwordStrength.label,
            style: TextStyle(
              fontSize: 12,
              color: _passwordStrength.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStrengthBarColor(int index) {
    final activeCount = _passwordStrength.barCount;
    if (index >= activeCount) return Colors.grey.shade300;
    return _passwordStrength.color;
  }

  Widget _buildVerifyingStatus() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Verifying...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isVerifying ? null : _verifyPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isVerifying
                  ? Icons.hourglass_empty_rounded
                  : (widget.forResults ? Icons.assessment_rounded : Icons.play_arrow_rounded),
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              _isVerifying
                  ? "Verifying..."
                  : (widget.forResults ? "View Results" : "Start Exam"),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return TextButton.icon(
      onPressed: _isVerifying
          ? null
          : () {
              if (mounted) Navigator.pop(context);
            },
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: const Text(
        "Back to Dashboard",
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6B7280),
      ),
    );
  }

  Widget _buildHelpButton() {
    return FloatingActionButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.help_rounded, color: Color(0xFFF59E0B)),
                SizedBox(width: 12),
                Text('Need Help?'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHelpItem('Ask your instructor for the exam password'),
                _buildHelpItem('Ensure stable internet connection'),
                _buildHelpItem('Use the correct student ID'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      },
      backgroundColor: const Color(0xFFF59E0B),
      child: const Icon(Icons.help_rounded, color: Colors.white),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

enum PasswordStrength {
  none(0, 'Enter password', Colors.grey),
  weak(1, 'Weak', Color(0xFFF44336)),
  medium(2, 'Medium', Color(0xFFF59E0B)),
  strong(4, 'Strong', Color(0xFF10B981));

  const PasswordStrength(this.barCount, this.label, this.color);
  final int barCount;
  final String label;
  final Color color;
}