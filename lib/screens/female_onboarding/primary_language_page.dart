import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';

class PrimaryLanguagePage extends StatefulWidget {
  final VoidCallback onNext;
  const PrimaryLanguagePage({super.key, required this.onNext});

  @override
  State<PrimaryLanguagePage> createState() => _PrimaryLanguagePageState();
}

class _PrimaryLanguagePageState extends State<PrimaryLanguagePage> {
  late String _selectedLang;

  final List<Map<String, String>> _languages = [
    {'name': 'Hindi', 'native': 'हिन्दी', 'symbol': 'अ'},
    {'name': 'English', 'native': 'English', 'symbol': 'A'},
    {'name': 'Telugu', 'native': 'తెలుగు', 'symbol': 'అ'},
    {'name': 'Bangla', 'native': 'বাংলা', 'symbol': 'অ'},
    {'name': 'Tamil', 'native': 'தமிழ்', 'symbol': 'அ'},
    {'name': 'Marathi', 'native': 'मराठी', 'symbol': 'अ'},
    {'name': 'Gujarati', 'native': 'ગુજરાતી', 'symbol': 'અ'},
    {'name': 'Kannada', 'native': 'ಕನ್ನಡ', 'symbol': 'ಅ'},
    {'name': 'Malayalam', 'native': 'മലയാളം', 'symbol': 'അ'},
    {'name': 'Punjabi', 'native': 'ਪੰਜਾਬੀ', 'symbol': 'ਅ'},
    {'name': 'Odia', 'native': 'ଓଡ଼ିଆ', 'symbol': 'ଓ'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedLang = context.read<AppState>().primaryLanguage;
  }

  void _submit() {
    context.read<AppState>().setPrimaryLanguage(_selectedLang);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        const Text(
          'Choose your',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppTheme.textGrey,
          ),
        ),
        const Text(
          'Primary Language',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBlack,
          ),
        ),
        const SizedBox(height: 30),

        // Custom list tiles
        Expanded(
          child: ListView.builder(
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final lang = _languages[index];
              final name = lang['name']!;
              final native = lang['native']!;
              final symbol = lang['symbol']!;
              final isSelected = _selectedLang == name;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedLang = name;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  height: 90,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.lightBlue : AppTheme.inputBg,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      children: [
                        // Large native symbol in the background
                        Positioned(
                          right: -10,
                          bottom: -20,
                          child: Text(
                            symbol,
                            style: TextStyle(
                              fontSize: 100,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.03),
                            ),
                          ),
                        ),
                        // Content
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    native,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                              Radio<String>.adaptive(
                                value: name,
                                  // ignore: deprecated_member_use
                                  groupValue: _selectedLang,
                                  activeColor: AppTheme.primaryBlue,
                                  // ignore: deprecated_member_use
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedLang = value;
                                      });
                                    }
                                  },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Next button
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Next'),
        ),
      ],
    );
  }
}
