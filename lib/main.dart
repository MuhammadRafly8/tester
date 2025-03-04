import 'dart:async';
import 'package:aisits_mobileapp/service/weather_service.dart';
import 'package:aisits_mobileapp/widget/error_boundary.dart';
import 'service/loading_service.dart';
import 'service/ship_provider.dart';
import 'service/json_service_provider.dart';
import 'package:flutter/material.dart';
import 'screen/login_screen.dart';
import 'screen/splash_screen.dart';
import 'screen/map_screen.dart';
import 'screen/alert_screen.dart';
import 'screen/danger_screen.dart';
import 'package:provider/provider.dart';
import 'service/notification_service.dart';
import 'widget/app_wrapper.dart';
import 'screen/weather_screen.dart';
import 'screen/markship_screen.dart';
import 'screen/logout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runZonedGuarded(() async {
    try {
      final jsonServiceProvider = JsonServiceProvider();
      await jsonServiceProvider.initializeData();
      final notificationService = NotificationService();
      final weatherService = WeatherService();
      final loadingService = LoadingService();  // Tambahkan ini
  
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: loadingService),  // Ubah ini
            ChangeNotifierProvider.value(value: notificationService),  
            ChangeNotifierProvider.value(value: jsonServiceProvider),
            Provider.value(value: weatherService),
            ChangeNotifierProvider(
              create: (context) => ShipProvider(
                jsonService: Provider.of<JsonServiceProvider>(context, listen: false).jsonService,
                notificationService: notificationService,
                onMarkerTap: (shipData) {
                  debugPrint("Marker tapped for ship: ${shipData.name}");
                },
              ),
            ),
          ],
          child: const MyApp(),
        ),
      );
    } catch (e, stack) {
      debugPrint('Error initializing application: $e\n$stack');
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Failed to initialize application: $e'),
          ),
        ),
      ));
    }
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      child: MaterialApp(
        title: 'Early Warning System',
        builder: (context, child) {
          return AppWrapper(child: child ?? const SizedBox());
        },
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Roboto',
          brightness: Brightness.light,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
        initialRoute: '/splash',
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/map': (context) => const MapScreen(),
          '/alert': (context) => const AlertScreen(),
          '/danger': (context) => const DangerScreen(),
          '/weather': (context) => const WeatherScreen(),
          '/markship': (context) => const MarkShipScreen(),
          '/logout': (context) => const LogoutScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
    }
  }

