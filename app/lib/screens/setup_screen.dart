import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  final bool isSetup;
  final VoidCallback? onUnlock;

  const SetupScreen({super.key, this.isSetup = false, this.onUnlock});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _codeController = TextEditingController();
  bool _isSetup = false;
  bool _showConfirm = false;
  String? _errorMessage;
  String _firstEntry = "";

  @override
  void initState() {
    super.initState();
    _checkIfSetupNeeded();
  }

  Future<void> _checkIfSetupNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final passcodeSet = prefs.getBool('passcode_set') ?? false;
    if (mounted) {
      setState(() {
        _isSetup = !passcodeSet || widget.isSetup;
      });
    }
  }

  Future<void> _submitPasscode() async {
    final code = _codeController.text.trim();

    if (code.length != 4) {
      setState(() => _errorMessage = "Enter exactly 4 digits.");
      return;
    }

    if (_isSetup) {
      if (!_showConfirm) {
        _firstEntry = code;
        setState(() {
          _showConfirm = true;
          _errorMessage = null;
          _codeController.clear();
        });
        return;
      }

      if (code != _firstEntry) {
        setState(() {
          _errorMessage = "Passcodes do not match.";
          _showConfirm = false;
          _firstEntry = "";
          _codeController.clear();
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passcode_hash', _firstEntry);
      await prefs.setBool('passcode_set', true);
      await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);

      if (widget.onUnlock != null) {
        widget.onUnlock!();
      } else {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString('passcode_hash') ?? '';

      if (code == savedHash) {
        await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
        if (widget.onUnlock != null) {
          widget.onUnlock!();
        }
      } else {
        setState(() {
          _errorMessage = "Incorrect passcode.";
          _codeController.clear();
        });
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_codeController.text.length < 4) {
      _codeController.text += digit;
      if (_codeController.text.length == 4) {
        _submitPasscode();
      }
    }
  }

  void _onDelete() {
    if (_codeController.text.isNotEmpty) {
      _codeController.text = _codeController.text.substring(0, _codeController.text.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, color: Color(0xFF8B5CF6), size: 56),
                const SizedBox(height: 16),
                Text(
                  _isSetup
                      ? (_showConfirm ? "Confirm Passcode" : "Set Passcode")
                      : "Enter Passcode",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSetup
                      ? "Create a 4-digit passcode to protect your app."
                      : "Enter your 4-digit passcode to unlock.",
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 32),

                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < _codeController.text.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? const Color(0xFF8B5CF6) : Colors.white24,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),

                _buildNumpad(),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitPasscode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _isSetup ? (_showConfirm ? "Confirm" : "Next") : "Unlock",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (!_isSetup)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('passcode_hash');
                        await prefs.remove('passcode_set');
                        if (mounted) {
                          setState(() {
                            _isSetup = true;
                            _showConfirm = false;
                            _errorMessage = null;
                            _codeController.clear();
                          });
                        }
                      },
                      child: const Text(
                        "Reset Passcode",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        _buildNumpadRow(["1", "2", "3"]),
        _buildNumpadRow(["4", "5", "6"]),
        _buildNumpadRow(["7", "8", "9"]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 72),
            _numpadKey("0"),
            GestureDetector(
              onTap: _onDelete,
              child: Container(
                width: 72,
                height: 56,
                alignment: Alignment.center,
                child: const Icon(Icons.backspace_outlined, color: Colors.white54, size: 24),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumpadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((k) => _numpadKey(k)).toList(),
    );
  }

  Widget _numpadKey(String digit) {
    return GestureDetector(
      onTap: () => _onDigit(digit),
      child: Container(
        width: 72,
        height: 56,
        margin: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          digit,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
