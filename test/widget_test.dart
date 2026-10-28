import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocky_call/app.dart';
import 'package:vocky_call/sandbox/sandbox_providers.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: sandboxOverrides,
        child: const VockyCallApp(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
