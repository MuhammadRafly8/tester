import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../service/json_service_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();
    _checkJsonLoaded();
  }

  Future<void> _checkJsonLoaded() async {
    try {
      final jsonProvider = Provider.of<JsonServiceProvider>(context, listen: false);
      if (!jsonProvider.isLoaded) {
        setState(() => _isLoading = true);
        await jsonProvider.initializeData();
        setState(() => _isLoading = false);
      }
      
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print('Error loading JSON data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _checkJsonLoaded,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _animation,
              child: ScaleTransition(
                scale: _animation,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Image.asset(
                    "assets/aislogo.png",
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text('Loading ship data...'),
            ],
          ],
        ),
      ),
    );
  }
}