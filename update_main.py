import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

replacement = """class SajniReApp extends StatefulWidget {
  const SajniReApp({super.key});

  @override
  State<SajniReApp> createState() => _SajniReAppState();
}

class _SajniReAppState extends State<SajniReApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Limit ImageCache size globally for memory optimization
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50 MB
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Clear bitmap memory when app goes to background (Android Vitals optimization)
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  @override
  Widget build(BuildContext context) {"""

content = content.replace("class SajniReApp extends StatelessWidget {\n  const SajniReApp({super.key});\n\n  @override\n  Widget build(BuildContext context) {", replacement)

with open('lib/main.dart', 'w') as f:
    f.write(content)
