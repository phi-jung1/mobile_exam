import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'student_dashboard.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;

  late AnimationController _controller;
  late Animation<Color?> _color1;
  late Animation<Color?> _color2;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _initHive();
  }

  void _setupAnimation() {
    _controller = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);

    _color1 = ColorTween(
      begin: const Color(0xFFB3E5FC),
      end: const Color(0xFF90CAF9),
    ).animate(_controller);

    _color2 = ColorTween(
      begin: const Color(0xFFE3F2FD),
      end: const Color(0xFFBBDEFB),
    ).animate(_controller);
  }

  Future<void> _initHive() async {
    try {
      final box = await Hive.openBox('loginBox');
      final savedId = box.get('studentId');
      final savedPassword = box.get('password'); // new
      final remember = box.get('rememberMe', defaultValue: false);

      if (remember && savedId != null && savedId.toString().isNotEmpty) {
        _idController.text = savedId.toString();
        _passwordController.text = savedPassword?.toString() ?? ''; // auto-fill password
        setState(() => _rememberMe = true);
      }
    } catch (e) {
      debugPrint("Hive initialization error: $e");
    }
  }

  Future<void> _login() async {
    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both ID and Password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Call Laravel API login
    final result = await ApiService.login(
      login: id,
      password: password,
    );

    setState(() => _isLoading = false);

    if (result != null && result['token'] != null && result['user'] != null) {
      // Login successful
      final token = result['token'];
      
      // ✅ Set the authentication token for API requests
      ApiService.setAuthToken(token);
      debugPrint('✅ Auth token set: ${token.substring(0, 20)}...');
      
      try {
        final box = await Hive.openBox('loginBox');
        final user = result['user'];
        
        debugPrint('👤 User data from API:');
        debugPrint('   id (database): ${user['id']}');
        debugPrint('   id_number (login): ${user['id_number']}');
        debugPrint('   first_name: ${user['first_name']}');
        debugPrint('   last_name: ${user['last_name']}');
        
        // Save token to Hive for persistence
        await box.put('authToken', token);
        
        if (_rememberMe) {
          await box.put('studentId', id);
          await box.put('password', password);
          await box.put('rememberMe', true);
          await box.put('user', jsonEncode(user)); // Save user data
        } else {
          await box.delete('studentId');
          await box.delete('password');
          await box.put('rememberMe', false);
        }

        if (!mounted) return;

        final firstName = user['first_name'] ?? '';
        final lastName = user['last_name'] ?? '';
        final fullName = '$firstName $lastName'.trim();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Welcome, ${fullName.isNotEmpty ? fullName : id}!")),
        );

        // Get the database ID (not the login id_number)
        final databaseId = user['id']?.toString();
        
        if (databaseId == null) {
          debugPrint('⚠️ WARNING: No database ID found in user object!');
          debugPrint('   This will cause issues with API calls.');
          debugPrint('   User object: $user');
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentDashboard(
              studentId: databaseId ?? user['id_number'] ?? id,  // Prefer database ID
              studentName: fullName.isNotEmpty ? fullName : null,  // Pass full name
            ),
          ),
        );
      } catch (e) {
        debugPrint("Hive save error: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login successful but failed to save info.")),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Invalid credentials or account not active"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  @override
  void dispose() {
    _controller.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _color1.value ?? const Color(0xFFB3E5FC),
                  _color2.value ?? const Color(0xFFE3F2FD),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/CicsLogo.png', width: 100),
                      const SizedBox(height: 20),
                      Text(
                        "MOBE",
                        style: GoogleFonts.lobster(
                          fontSize: 36,
                          color: Colors.blueAccent.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Mobile-Based Examination",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 30),
                      // -------------------- Login Card --------------------
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Student ID
                            TextField(
                              controller: _idController,
                              decoration: const InputDecoration(
                                labelText: "Student ID",
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Password
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Remember Me
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (value) =>
                                      setState(() => _rememberMe = value ?? false),
                                ),
                                const Text("Remember Me"),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        "Login",
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.white),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // ✅ Removed Forgot Password Button
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Login with your Student ID and Password",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

}
