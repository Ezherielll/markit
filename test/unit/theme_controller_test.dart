import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cycle: light → dark → system → light', () {
    final controller = ThemeController(initial: ThemeMode.light);

    controller.cycle();
    expect(controller.mode, ThemeMode.dark);
    controller.cycle();
    expect(controller.mode, ThemeMode.system);
    controller.cycle();
    expect(controller.mode, ThemeMode.light);
  });

  test('persist & load ulang (disk/localStorage)', () async {
    SharedPreferences.setMockInitialValues({});

    final c1 = ThemeController(initial: ThemeMode.light);
    c1.cycle(); // → dark, persist (async)
    expect(c1.mode, ThemeMode.dark);
    // Tunggu persist async selesai.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Controller baru = simulasi restart app.
    final c2 = ThemeController(initial: ThemeMode.system);
    await c2.load();
    expect(c2.mode, ThemeMode.dark);
  });

  test('load: nilai tidak dikenal → system (default)', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'unknown'});
    final controller = ThemeController(initial: ThemeMode.system);
    await controller.load();
    expect(controller.mode, ThemeMode.system);
  });
}
