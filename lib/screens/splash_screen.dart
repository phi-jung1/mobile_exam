import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool showM = false;
  bool showTagline = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  late AnimationController _gradientController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  late Timer navigationTimer;

  @override
  void initState() {
    super.initState();

    // Logo scale (burst) animation
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    );

    // Flip animation controller (O → M)
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _flipAnimation =
        Tween<double>(begin: 0.0, end: pi).animate(CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOut,
    ));

    // Gradient background animation
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    // Tagline fade-in animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Start sequence
    _scaleController.forward();

    // Trigger letter flip (O → M)
    Future.delayed(const Duration(milliseconds: 1500), () {
      _flipController.forward().then((_) {
        setState(() {
          showM = true;
        });
      });
    });

    // Show tagline before navigation
    Future.delayed(const Duration(milliseconds: 3200), () {
      setState(() => showTagline = true);
      _fadeController.forward();
    });

    // Navigate to Login screen
    navigationTimer = Timer(const Duration(seconds: 5), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    });
  }

  @override
  void dispose() {
    navigationTimer.cancel();
    _flipController.dispose();
    _gradientController.dispose();
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.lobster(
      fontSize: 36,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      shadows: [
        Shadow(
          blurRadius: 15,
          color: Colors.blue.shade200.withOpacity(0.9),
          offset: const Offset(0, 0),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, child) {
        final value = _gradientController.value;

        // Moving gradient colors and direction
        final colors = [
          Color.lerp(const Color(0xFF1565C0), const Color(0xFF42A5F5), value)!,
          Color.lerp(const Color(0xFF42A5F5), const Color(0xFF90CAF9), value)!,
        ];

        final alignment = Alignment(
          -1 + 2 * value,
          1 - 2 * value,
        );

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: alignment,
                end: Alignment.bottomRight,
              ),
            ),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Image.asset('assets/CicsLogo.png', width: 120),
                    const SizedBox(height: 20),

                    Text(
                      'College of Information and Computing Sciences',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Flip animation O → M
                    AnimatedBuilder(
                      animation: _flipAnimation,
                      builder: (context, child) {
                        final isFirstHalf = _flipAnimation.value < pi / 2;
                        final rotationValue = isFirstHalf
                            ? _flipAnimation.value
                            : _flipAnimation.value - pi;

                        return Transform(
                          transform: Matrix4.rotationY(rotationValue),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(isFirstHalf ? 'O' : 'M', style: textStyle),
                              Text('obe', style: textStyle),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Tagline Fade-In
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        showTagline
                            ? 'Empowering Digital Minds...'
                            : '',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                    const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
