import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  bool _initialized = false;
  bool useMockAds = true; // Set to false to use real Google AdMob ads

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (!useMockAds) {
        await MobileAds.instance.initialize();
      }
      _initialized = true;
    } catch (e) {
      debugPrint("Google Mobile Ads Initialization Error: $e");
    }
  }

  // Helper to get demo Ad Unit ID
  String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3676275694536393/7251475065'; // Real Android Rewarded Ad Unit ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // iOS Test Rewarded Ad Unit ID
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

  // Simulates ad viewing with a beautiful interactive progress dialog
  Future<bool> _showMockAd(BuildContext context) async {
    final completer = Completer<bool>();
    int secondsRemaining = 3;
    Timer? timer;

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
                    const Text(
                      "Просмотр рекламы",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Пожалуйста, подождите. VPN подключится автоматически после завершения видео.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
          
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(false); // User closed ad early or failed
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              completer.complete(true); // Fallback: allow connection if ad fails to show
            },
          );

          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              if (!completer.isCompleted) {
                completer.complete(true); // Reward earned!
              }
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
