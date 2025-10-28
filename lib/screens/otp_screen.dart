import 'package:flutter/material.dart';
import 'results_screen.dart';
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
  final TextEditingController otpController = TextEditingController();
  bool isVerifying = false;
  bool isError = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation =
        Tween<double>(begin: 0, end: 10).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
  }

  Future<void> verifyOTP() async {
    final enteredPassword = otpController.text.trim();

    if (enteredPassword.isEmpty) {
      setState(() {
        isError = true;
      });
      _shakeController.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("❌ Please enter the exam password."),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      isVerifying = true;
      isError = false;
    });

    // Call API to verify password
    debugPrint('🔐 Verifying password for exam ${widget.examId} with API...');
    debugPrint('   📋 Exam ID (string): "${widget.examId}"');
    debugPrint('   👤 Student ID (string): "${widget.studentId}"');
    
    // Parse IDs
    int examIdInt;
    int studentIdInt;
    
    try {
      examIdInt = int.parse(widget.examId);
      debugPrint('   ✅ Parsed exam ID: $examIdInt');
    } catch (e) {
      debugPrint('   ❌ Failed to parse exam ID "${widget.examId}": $e');
      setState(() {
        isError = true;
        isVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Invalid exam ID: ${widget.examId}"),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }
    
    try {
      studentIdInt = int.parse(widget.studentId);
      debugPrint('   ✅ Parsed student ID: $studentIdInt');
    } catch (e) {
      debugPrint('   ❌ Failed to parse student ID "${widget.studentId}": $e');
      setState(() {
        isError = true;
        isVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Invalid student ID: ${widget.studentId}"),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }
    
    final verified = await ApiService.verifyExamPassword(
      examId: examIdInt,
      studentId: studentIdInt,
      password: enteredPassword,
    );

    if (!mounted) return;

    if (verified) {
      // Password is correct
      debugPrint('✅ Password verified successfully');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.forResults
              ? "✅ Password Verified! Loading Results..."
              : "✅ Password Verified! Starting Exam..."),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

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
        widget.onVerified?.call();
      }
    } else {
      // Password is incorrect or verification failed
      debugPrint('❌ Password verification failed');
      
      setState(() {
        isError = true;
        isVerifying = false;
      });
      _shakeController.forward(from: 0);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("❌ Incorrect password. Please try again."),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (mounted && isVerifying) {
      setState(() => isVerifying = false);
    }
  }

  @override
  void dispose() {
    otpController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.forResults ? "Verify Password to View Results" : "Verify Password to Start Exam";

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
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 60,
                        color: Colors.blueAccent.shade700,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subject,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.blueGrey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      // Animated OTP box
                      AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(isError ? _shakeAnimation.value : 0, 0),
                            child: child,
                          );
                        },
                        child: TextField(
                          controller: otpController,
                          keyboardType: TextInputType.text,
                          obscureText: true,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            counterText: "",
                            hintText: "Enter password",
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isError ? Colors.red : Colors.blueAccent, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isError
                                      ? Colors.red.shade300
                                      : Colors.grey.shade400,
                                  width: 1.5),
                            ),
                            prefixIcon: const Icon(Icons.password_rounded),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      
                      // Show verification progress
                      if (isVerifying)
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
                      
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: isVerifying ? null : verifyOTP,
                          icon: isVerifying
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
                            isVerifying
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
                            elevation: 5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
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
