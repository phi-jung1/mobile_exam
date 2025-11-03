import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'results_screen.dart';
import 'exam_screen.dart';
import '../services/api_service.dart';

class OTPScreen extends StatefulWidget {
  final String examId;
  final String subject;
  final String? expectedOTP;  // Deprecated - kept for backward compatibility
  final bool forResults;
  final String studentId;
  final VoidCallback? onVerified;

  const OTPScreen({
    super.key,
    required this.examId,
    required this.subject,
    this.expectedOTP,
    this.forResults = false,
    required this.studentId,
    this.onVerified,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isVerifying = false;
  bool _isError = false;
  bool _disposed = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

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
        message: "❌ Please enter the exam password",
        success: false,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isVerifying = true;
      _isError = false;
    });

    // Parse IDs for API call
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
        message: "❌ Invalid exam ID: ${widget.examId}",
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
        message: "❌ Invalid student ID: ${widget.studentId}",
        success: false,
      );
      return;
    }

    if (kDebugMode) {
      debugPrint('🔐 Verifying password for exam $examIdInt with API...');
    }

    // Call API to verify password
    final verified = await ApiService.verifyExamPassword(
      examId: examIdInt,
      studentId: studentIdInt,
      password: enteredPassword,
    );

    if (_disposed || !mounted) return;

    if (verified) {
      // Password is correct
      if (kDebugMode) {
        debugPrint('✅ Password verified successfully');
      }
      HapticFeedback.lightImpact();
      
      _showFloatingMessage(
        message: widget.forResults
            ? "✅ Password Verified! Loading Results..."
            : "✅ Password Verified! Starting Exam...",
        success: true,
      );

      await Future.delayed(const Duration(milliseconds: 800));

      if (_disposed || !mounted) return;

      // Navigate to appropriate screen
      if (widget.forResults) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultsScreen(
              examId: widget.examId,
              studentId: widget.studentId,
            ),
          ),
        );
      } else {
        // If onVerified callback is provided, use it
        if (widget.onVerified != null) {
          widget.onVerified!();
        } else {
          // Otherwise navigate directly to exam screen
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
      // Password is incorrect
      if (kDebugMode) {
        debugPrint('❌ Password verification failed');
      }
      HapticFeedback.heavyImpact();
      
      if (!mounted) return;
      setState(() {
        _isError = true;
        _isVerifying = false;
      });
      _shakeController.forward(from: 0);
      
      _showFloatingMessage(
        message: "❌ Incorrect password. Please try again.",
        success: false,
      );
      
      // Clear the password field
      passwordController.clear();
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
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: success ? Colors.green.shade600 : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    passwordController.dispose();
    _shakeController.dispose();
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
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Lock Icon with animation
                      Hero(
                        tag: 'password-lock-${widget.examId}',
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: Colors.blue.shade50,
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 48,
                            color: Colors.blueAccent.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      
                      // Subject
                      Text(
                        widget.subject,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.blueGrey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      
                      // Subtitle
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      // Password Input with Shake Animation
                      AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_isError ? _shakeAnimation.value : 0, 0),
                            child: child,
                          );
                        },
                        child: TextField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: "Enter password",
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                            prefixIcon: const Icon(Icons.password_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                if (!mounted) return;
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _isError ? Colors.red : Colors.blueAccent,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _isError
                                    ? Colors.red.shade300
                                    : Colors.grey.shade400,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _verifyPassword(),
                        ),
                      ),

                      const SizedBox(height: 24),
                      
                      // Verification Status
                      if (_isVerifying)
                        Padding(
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
                        ),
                      
                      // Verify Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isVerifying ? null : _verifyPassword,
                          icon: _isVerifying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.verified_user),
                          label: Text(
                            _isVerifying
                                ? "Verifying..."
                                : (widget.forResults
                                    ? "Verify & View Results"
                                    : "Verify & Start Exam"),
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Back Button
                      TextButton.icon(
                        onPressed: () {
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Back to Dashboard"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}