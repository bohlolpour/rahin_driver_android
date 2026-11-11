import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/home_screen.dart';

class MainNav extends StatefulWidget {
  final String driverId;

  const MainNav({super.key, required this.driverId});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  @override
  Widget build(BuildContext context) {
    return HomeScreen(driverId: widget.driverId);
  }
}