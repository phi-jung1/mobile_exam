import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  // NEW: Exam details for enhanced display
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
    
    // Shake animation for errors
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
    
    // Pulse animation for lock icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_pulseController);
    
    // Success animation
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) {
        _focusNode.requestFocus();
      }
    });
    
    // Listen to password changes for strength indicator
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

    // Parse IDs
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

    // Call API
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

      // Navigate
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
              size: 22,
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
        backgroundColor: success ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
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
        ? "Verify Password to View Results"
        : "Verify Password to Start Exam";

    final subtitle = widget.forResults
        ? "Enter the exam password provided by your instructor to access your results."
        : "Enter the exam password provided by your instructor to begin your exam.";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Card(
                elevation: 20,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated Lock Icon
                      _buildLockIcon(),
                      const SizedBox(height: 24),
                      
                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212121),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      
                      // Subject/Exam Title
                      Text(
                        widget.examTitle ?? widget.subject,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF1976D2),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      
                      // Subtitle
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      // Exam Details Card (if provided)
                      if (!widget.forResults && _hasExamDetails())
                        _buildExamDetailsCard(),
                      
                      const SizedBox(height: 24),

                      // Helper Text
                      _buildHelperText(),
                      
                      const SizedBox(height: 16),

                      // Password Input with Animation
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

                      // Password Strength Indicator
                      if (_passwordStrength != PasswordStrength.none)
                        _buildStrengthIndicator(),

                      const SizedBox(height: 24),
                      
                      // Verification Status
                      if (_isVerifying) _buildVerifyingStatus(),
                      
                      // Verify Button
                      _buildVerifyButton(),
                      
                      const SizedBox(height: 16),
                      
                      // Back Button
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
        // Pulsing Circle
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE3F2FD),
                  const Color(0xFFBBDEFB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        ),
        
        // Lock Icon or Success Checkmark
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _isSuccess
              ? ScaleTransition(
                  scale: _successController,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 52,
                    color: Color(0xFF4CAF50),
                    key: ValueKey('success'),
                  ),
                )
              : Icon(
                  Icons.lock_rounded,
                  size: 48,
                  color: const Color(0xFF1976D2),
                  key: const ValueKey('lock'),
                ),
        ),
        
        // Security Badge
        if (!_isSuccess)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }

  bool _hasExamDetails() {
    return widget.examDate != null ||
        widget.examTime != null ||
        widget.duration != null ||
        widget.questionCount != null;
  }

  Widget _buildExamDetailsCard() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade50,
            Colors.grey.shade100,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          if (widget.examDate != null || widget.examTime != null)
            _buildDetailRow(
              Icons.calendar_today_rounded,
              '${widget.examDate ?? ''} ${widget.examTime ?? ''}'.trim(),
            ),
          if (widget.duration != null)
            _buildDetailRow(Icons.timer_rounded, 'Duration: ${widget.duration}'),
          if (widget.questionCount != null)
            _buildDetailRow(Icons.quiz_rounded, '${widget.questionCount} questions'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1976D2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF424242),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelperText() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF2196F3), width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded, color: Color(0xFF1565C0), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Contact your instructor if you don't have the password",
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: TextField(
        controller: passwordController,
        focusNode: _focusNode,
        obscureText: _obscurePassword,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          letterSpacing: _obscurePassword ? 8.0 : 1.2,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: "Enter password",
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 16,
            letterSpacing: 1.0,
          ),
          prefixIcon: Icon(
            Icons.key_rounded,
            size: 22,
            color: _isError
                ? Colors.red
                : _isSuccess
                    ? const Color(0xFF4CAF50)
                    : Colors.grey.shade600,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 22,
            ),
            onPressed: () {
              setState(() => _obscurePassword = !_obscurePassword);
            },
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          ),
          filled: true,
          fillColor: _isError
              ? const Color(0xFFFFEBEE)
              : _isSuccess
                  ? const Color(0xFFE8F5E9)
                  : Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _isError
                  ? const Color(0xFFF44336)
                  : _isSuccess
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF2196F3),
              width: 2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _isError
                  ? Colors.red.shade300
                  : _isSuccess
                      ? const Color(0xFF4CAF50)
                      : Colors.grey.shade300,
              width: 2,
            ),
          ),
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _verifyPassword(),
        enabled: !_isVerifying,
      ),
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
                  margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
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
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 8),
          Text(
            'Verifying with server...',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isVerifying ? null : _verifyPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          shadowColor: Colors.blue.withOpacity(0.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isVerifying)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.verified_user_rounded, size: 22),
            const SizedBox(width: 10),
            Text(
              _isVerifying
                  ? "Verifying..."
                  : (widget.forResults ? "Verify & View Results" : "Verify & Start Exam"),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isVerifying
            ? null
            : () {
                if (mounted) Navigator.pop(context);
              },
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        label: const Text(
          "Back to Dashboard",
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1976D2),
          side: BorderSide(color: Colors.grey.shade300, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
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
                Icon(Icons.help_rounded, color: Color(0xFFFF9800)),
                SizedBox(width: 12),
                Text('Need Help?'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHelpItem('Contact your instructor for the exam password'),
                _buildHelpItem('Ensure you have a stable internet connection'),
                _buildHelpItem('Make sure you\'re using the correct student ID'),
                const SizedBox(height: 16),
                const Text(
                  'For technical support, contact your system administrator.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
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
      backgroundColor: const Color(0xFFFF9800),
      child: const Icon(Icons.help_rounded, color: Colors.white),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 18, color: Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
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
  medium(2, 'Medium', Color(0xFFFF9800)),
  strong(4, 'Strong', Color(0xFF4CAF50));

  const PasswordStrength(this.barCount, this.label, this.color);
  final int barCount;
  final String label;
  final Color color;
}