import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const SafeHerApp());
}

class SafeHerApp extends StatelessWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeHer AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // VOICE SERVICES
  // ============================================================

  final stt.SpeechToText speech = stt.SpeechToText();
  final FlutterTts flutterTts = FlutterTts();

  // ============================================================
  // SETTINGS
  // ============================================================

  String emergencyPhrase = 'Blue Sky';
  String emergencyContact = '';

  bool listenerEnabled = false;
  bool emergencyMode = false;
  bool speechAvailable = false;
  bool restartingSpeech = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
    initializeTts();
  }

  // ============================================================
  // TEXT TO SPEECH INITIALIZATION
  // ============================================================

  Future<void> initializeTts() async {
    try {
      await flutterTts.setLanguage('en-US');
      await flutterTts.setSpeechRate(0.45);
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  // ============================================================
  // SPEAK
  // ============================================================

  Future<void> speak(String text) async {
    try {
      await flutterTts.stop();

      await flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      emergencyPhrase =
          prefs.getString('phrase') ?? 'Blue Sky';

      emergencyContact =
          prefs.getString('contact') ?? '';
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'phrase',
      emergencyPhrase,
    );

    await prefs.setString(
      'contact',
      emergencyContact,
    );
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<Position?> getLocation() async {
    bool serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable location services.',
            ),
          ),
        );
      }

      return null;
    }

    LocationPermission permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
      await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission denied.',
            ),
          ),
        );
      }

      return null;
    }

    try {
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint('Location error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to get current location.',
            ),
          ),
        );
      }

      return null;
    }
  }

  // ============================================================
  // EMERGENCY ACTION
  // ============================================================

  Future<void> emergencyAction() async {
    setState(() {
      emergencyMode = true;
    });

    await speak(
      'Emergency mode activated.',
    );

    final position = await getLocation();

    if (!mounted) return;

    String message =
        'Emergency alert! I may need assistance.';

    if (position != null) {
      final mapsLink =
          'https://www.google.com/maps/search/?api=1'
          '&query=${position.latitude},${position.longitude}';

      message =
      'Emergency alert! I may need assistance. '
          'My current location: $mapsLink';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Emergency alert prepared.',
        ),
        duration: Duration(seconds: 4),
      ),
    );

    // ==========================================================
    // OPEN SMS
    // ==========================================================

    if (emergencyContact.isNotEmpty) {
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: emergencyContact,
        queryParameters: {
          'body': message,
        },
      );

      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'SMS application is not available.',
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('SMS error: $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to open SMS application.',
              ),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please set an emergency contact first.',
            ),
          ),
        );
      }
    }
  }

  // ============================================================
  // START VOICE LISTENER
  // ============================================================

  Future<void> startSafetyListener() async {
    if (listenerEnabled) {
      return;
    }

    try {
      speechAvailable = await speech.initialize(
        onStatus: (status) {
          debugPrint(
            'Speech status: $status',
          );

          if (status == 'done' &&
              listenerEnabled &&
              !restartingSpeech) {
            restartSpeechListener();
          }
        },

        onError: (error) {
          debugPrint(
            'Speech error: ${error.errorMsg}',
          );

          if (mounted) {
            setState(() {
              listenerEnabled = false;
            });

            speak(
              'Voice recognition is unavailable.',
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Voice recognition is unavailable on this device.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
          }
        },
      );

      if (!speechAvailable) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Speech recognition is not available.',
            ),
          ),
        );

        return;
      }

      setState(() {
        listenerEnabled = true;
      });

      // ========================================================
      // VOICE PROMPT
      // ========================================================

      await speak(
        'Safety voice listener activated. '
            'Please say your secret safety phrase.',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listening... Say "$emergencyPhrase"',
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      await startListeningAgain();
    } catch (e) {
      debugPrint(
        'Speech initialization error: $e',
      );

      if (!mounted) return;

      setState(() {
        listenerEnabled = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to start voice recognition.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // LISTEN
  // ============================================================

  Future<void> startListeningAgain() async {
    if (!listenerEnabled) {
      return;
    }

    try {
      if (speech.isListening) {
        await speech.stop();
      }

      await Future.delayed(
        const Duration(
          milliseconds: 300,
        ),
      );

      if (!listenerEnabled) {
        return;
      }

      await speech.listen(
        onResult: (result) {
          final words =
          result.recognizedWords.toLowerCase();

          final phrase =
          emergencyPhrase.toLowerCase();

          debugPrint(
            'Heard: $words',
          );

          // ====================================================
          // SECRET PHRASE DETECTED
          // ====================================================

          if (words.contains(phrase)) {
            debugPrint(
              'Emergency phrase detected!',
            );

            speak(
              'Safety phrase detected. '
                  'Emergency assistance is being prepared.',
            );

            emergencyAction();

            stopSafetyListener();
          }
        },

        listenFor: const Duration(
          seconds: 15,
        ),

        pauseFor: const Duration(
          seconds: 3,
        ),
      );
    } catch (e) {
      debugPrint(
        'Voice listener error: $e',
      );

      if (!mounted) return;

      setState(() {
        listenerEnabled = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice recognition stopped.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // RESTART VOICE LISTENER
  // ============================================================

  Future<void> restartSpeechListener() async {
    if (!listenerEnabled ||
        restartingSpeech) {
      return;
    }

    restartingSpeech = true;

    try {
      await Future.delayed(
        const Duration(
          milliseconds: 500,
        ),
      );

      if (listenerEnabled) {
        await startListeningAgain();
      }
    } finally {
      restartingSpeech = false;
    }
  }

  // ============================================================
  // STOP VOICE LISTENER
  // ============================================================

  Future<void> stopSafetyListener() async {
    if (mounted) {
      setState(() {
        listenerEnabled = false;
      });
    }

    try {
      await speech.stop();
      await flutterTts.stop();
    } catch (e) {
      debugPrint(
        'Speech stop error: $e',
      );
    }
  }

  // ============================================================
  // EMERGENCY CONTACT
  // ============================================================

  Future<void> editEmergencyContact() async {
    final controller =
    TextEditingController(
      text: emergencyContact,
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Emergency Contact',
          ),

          content: TextField(
            controller: controller,
            keyboardType:
            TextInputType.phone,

            decoration:
            const InputDecoration(
              labelText: 'Phone number',
              hintText:
              'Enter emergency contact number',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },

              child: const Text(
                'Cancel',
              ),
            ),

            ElevatedButton(
              onPressed: () async {
                emergencyContact =
                    controller.text.trim();

                await saveSettings();

                if (mounted) {
                  setState(() {});

                  Navigator.pop(context);
                }
              },

              child: const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SECRET SAFETY PHRASE
  // ============================================================

  Future<void> editPhrase() async {
    final controller =
    TextEditingController(
      text: emergencyPhrase,
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Secret Safety Phrase',
          ),

          content: TextField(
            controller: controller,

            decoration:
            const InputDecoration(
              labelText: 'Secret phrase',
              hintText:
              'Example: Blue Sky',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },

              child: const Text(
                'Cancel',
              ),
            ),

            ElevatedButton(
              onPressed: () async {
                if (controller.text
                    .trim()
                    .isEmpty) {
                  return;
                }

                emergencyPhrase =
                    controller.text.trim();

                await saveSettings();

                if (mounted) {
                  setState(() {});

                  Navigator.pop(context);
                }
              },

              child: const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SafeHer AI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding:
        const EdgeInsets.all(20),

        child: Column(
          children: [
            const SizedBox(
              height: 10,
            ),

            const Text(
              'Your Safety Companion',

              style: TextStyle(
                fontSize: 25,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            const Text(
              'Smart emergency assistance using '
                  'voice detection and location.',

              textAlign:
              TextAlign.center,
            ),

            const SizedBox(
              height: 30,
            ),

            // ==================================================
            // SOS BUTTON
            // ==================================================

            GestureDetector(
              onTap: emergencyAction,

              child: Container(
                width: 140,
                height: 140,

                decoration:
                const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),

                child: const Center(
                  child: Icon(
                    Icons.emergency,
                    color: Colors.white,
                    size: 65,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            const Text(
              'EMERGENCY SOS',

              style: TextStyle(
                color: Colors.red,
                fontWeight:
                FontWeight.bold,
                fontSize: 16,
              ),
            ),

            const SizedBox(
              height: 30,
            ),

            // ==================================================
            // SECRET PHRASE
            // ==================================================

            Card(
              child: ListTile(
                leading:
                const Icon(
                  Icons.lock,
                ),

                title: const Text(
                  'Secret Safety Phrase',
                ),

                subtitle: Text(
                  emergencyPhrase,
                ),

                trailing:
                const Icon(
                  Icons.edit,
                ),

                onTap: editPhrase,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            // ==================================================
            // EMERGENCY CONTACT
            // ==================================================

            Card(
              child: ListTile(
                leading:
                const Icon(
                  Icons.contact_phone,
                ),

                title: const Text(
                  'Emergency Contact',
                ),

                subtitle: Text(
                  emergencyContact.isEmpty
                      ? 'Not set'
                      : emergencyContact,
                ),

                trailing:
                const Icon(
                  Icons.edit,
                ),

                onTap:
                editEmergencyContact,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            // ==================================================
            // VOICE LISTENER
            // ==================================================

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      listenerEnabled
                          ? Icons.mic
                          : Icons.mic_none,

                      color: listenerEnabled
                          ? Colors.green
                          : Colors.grey,
                    ),

                    title: const Text(
                      'Safety Voice Listener',
                    ),

                    subtitle: Text(
                      listenerEnabled
                          ? 'Listening...'
                          : 'Listener is OFF',
                    ),

                    trailing: Switch(
                      value:
                      listenerEnabled,

                      onChanged: (value) {
                        if (value) {
                          startSafetyListener();
                        } else {
                          stopSafetyListener();
                        }
                      },
                    ),
                  ),

                  // =================================================
                  // LISTENING STATUS
                  // =================================================

                  if (listenerEnabled)
                    Container(
                      width: double.infinity,

                      margin:
                      const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),

                      padding:
                      const EdgeInsets.all(16),

                      decoration:
                      BoxDecoration(
                        color:
                        Colors.green.shade50,

                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),

                        border: Border.all(
                          color:
                          Colors.green.shade300,
                        ),
                      ),

                      child: Column(
                        children: [
                          const Icon(
                            Icons.mic,
                            color:
                            Colors.green,
                            size: 32,
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          const Text(
                            'LISTENING...',
                            style: TextStyle(
                              color:
                              Colors.green,
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          const Text(
                            'Please say your secret safety phrase:',
                            textAlign:
                            TextAlign.center,
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          Text(
                            '"$emergencyPhrase"',

                            textAlign:
                            TextAlign.center,

                            style:
                            const TextStyle(
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // EMERGENCY STATUS
            // ==================================================

            if (emergencyMode)
              Card(
                color:
                Colors.red.shade50,

                child: const Padding(
                  padding:
                  EdgeInsets.all(16),

                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Colors.red,
                      ),

                      SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child: Text(
                          'Emergency mode activated.',

                          style: TextStyle(
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // LOCATION TEST
            // ==================================================

            OutlinedButton.icon(
              onPressed: () async {
                final position =
                await getLocation();

                if (!mounted) return;

                if (position != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Location: '
                            '${position.latitude}, '
                            '${position.longitude}',
                      ),
                    ),
                  );
                }
              },

              icon: const Icon(
                Icons.location_on,
              ),

              label: const Text(
                'Test My Location',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    speech.stop();
    flutterTts.stop();
    super.dispose();
  }
}