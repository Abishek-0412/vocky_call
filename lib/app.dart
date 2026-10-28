/// App router — declarative GoRouter with two routes.
library app;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vocky_call/presentation/features/call/call_screen.dart';
import 'package:vocky_call/presentation/features/home/home_screen.dart';
import 'package:vocky_call/presentation/shared/theme/app_theme.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/call',
      builder: (_, __) => const CallScreen(),
    ),
  ],
);

class VockyCallApp extends ConsumerWidget {
  const VockyCallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'VockyCall',
      theme: AppTheme.dark,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
