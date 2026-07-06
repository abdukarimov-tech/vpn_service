import 'dart:async';
import 'dart:io';
import 'package:client/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  bool _initialized = false;
  bool useMockAds = false; // Set to true to use the fake countdown dialog instead of AdMob
  bool useTestAds = true; // Test build: Google sample rewarded ad units (safe for Play review / internal testing).

  // Devices registered here receive TEST ads even with production ad unit IDs
  // (safe to click, no policy risk). Add device IDs from logcat:
  // "Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("...")) to get test ads on this device."
  static const List<String> _testDeviceIds = <String>[
    '8583B32A0E17D4268006346FD6E40690',
  ];

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (!useMockAds) {
        if (_testDeviceIds.isNotEmpty) {
          MobileAds.instance.updateRequestConfiguration(
            RequestConfiguration(testDeviceIds: _testDeviceIds),
          );
        }
        await MobileAds.instance.initialize();
      }
      _initialized = true;
    } catch (e) {
      debugPrint("Google Mobile Ads Initialization Error: $e");
    }
  }

  // Google's official test rewarded ad units. They always serve a test ad and
  // are safe to click on any device (no policy risk).
  static const String _androidTestRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _iosTestRewarded = 'ca-app-pub-3940256099942544/1712485313';

  // Your real (production) rewarded ad units.
  static const String _androidRealRewarded = 'ca-app-pub-3676275694536393/7251475065';
  static const String _iosRealRewarded = 'ca-app-pub-3676275694536393/8902101107';

  String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      return useTestAds ? _androidTestRewarded : _androidRealRewarded;
    } else if (Platform.isIOS) {
      return useTestAds ? _iosTestRewarded : _iosRealRewarded;
    }
    return '';
  }

  // Shows ad and returns true if user earned reward (watched the ad)
  Future<bool> showAd(BuildContext context) async {
    if (useMockAds) {
      return await _showMockAd(context);
    }
    return await _showAdMobRewardedAd(context);
  }

  void _hideSystemBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Simulates ad viewing with a beautiful interactive progress dialog
  Future<bool> _showMockAd(BuildContext context) async {
    final completer = Completer<bool>();
    int secondsRemaining = 3;
    Timer? timer;

    final settings = Provider.of<SettingsProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (secondsRemaining > 1) {
                setState(() {
                  secondsRemaining--;
                });
              } else {
                t.cancel();
                Navigator.of(dialogContext).pop();
                completer.complete(true);
              }
            });

            return PopScope(
              canPop: false, // Prevent dismissal
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E1E2C),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.ondemand_video,
                      size: 48,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      settings.translate('ad_watching_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.translate('ad_watching_desc'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                          ),
                        ),
                        Text(
                          "$secondsRemaining",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return completer.future;
  }

  // Shows real AdMob Rewarded Ad
  Future<bool> _showAdMobRewardedAd(BuildContext context) async {
    final completer = Completer<bool>();
    
    // Show a loading spinner while ad fetches
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
        ),
      ),
    );

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          Navigator.of(context).pop(); // Dismiss loading spinner

          // Track the reward separately from dismissal. The reward fires while
          // the ad is still on screen, so we must NOT restore the system bars
          // (or complete) until the ad is actually closed - otherwise the status
          // bar reappears over the ad content.
          bool rewardEarned = false;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              _hideSystemBars();
            },
            onAdDismissedFullScreenContent: (ad) {
              _restoreSystemBars();
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(rewardEarned);
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _restoreSystemBars();
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(true); // Fallback: allow connection if ad fails to show
              }
            },
          );

          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              rewardEarned = true; // Marked; connection happens once the ad closes
            },
          );
        },
        onAdFailedToLoad: (error) {
          Navigator.of(context).pop(); // Dismiss loading spinner
          debugPrint("RewardedAd failed to load: $error");
          // Fallback to mock ad if ad server is unreachable
          completer.complete(_showMockAd(context));
        },
      ),
    );

    return completer.future;
  }
}
