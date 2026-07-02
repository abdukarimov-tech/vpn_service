import 'package:client/providers/vpn_provider.dart';
import 'package:client/screens/servers_screen.dart';
import 'package:client/services/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Auto initialize VPN provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<VpnProvider>(context, listen: false).init();
      AdService().init();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleConnectTap(VpnProvider provider) async {
    if (provider.isConnected) {
      // Disconnect directly
      await provider.disconnect();
      _pulseController.stop();
    } else if (provider.vpnState == 'DISCONNECTED' || provider.vpnState == 'DENIED') {
      // Show ad first, then connect on success
      final watchedAd = await AdService().showAd(context);
      if (!mounted) return;
      if (watchedAd) {
        await provider.connect();
        _pulseController.repeat(reverse: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Необходимо досмотреть видео для подключения к VPN"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VpnProvider>(context);

    // Keep pulse animation updated based on status
    if (provider.isConnected && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!provider.isConnected && _pulseController.isAnimating) {
      _pulseController.stop();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/icon.png',
                  height: 32,
                  width: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "FREE VPN",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              // Quick config toggle mock/real ads
              setState(() {
                AdService().useMockAds = !AdService().useMockAds;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AdService().useMockAds 
                        ? "Включен тестовый режим рекламы" 
                        : "Включен режим реальной рекламы AdMob",
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
              ),
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Connection status text & duration
                  Column(
                    children: [
                      Text(
                        provider.vpnState == 'CONNECTED'
                            ? "ЗАЩИЩЕНО"
                            : provider.vpnState == 'CONNECTING'
                                ? "ПОДКЛЮЧЕНИЕ..."
                                : "ОТКЛЮЧЕНО",
                        style: TextStyle(
                          color: provider.isConnected ? Colors.greenAccent : Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.vpnDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w300,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ],
                  ),

                  // Neon Connect Button
                  GestureDetector(
                    onTap: () => _handleConnectTap(provider),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glowing waves
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              width: 220 * _pulseAnimation.value,
                              height: 220 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: provider.isConnected
                                    ? Colors.green.withValues(alpha: 0.04)
                                    : Colors.cyan.withValues(alpha: 0.04),
                              ),
                            );
                          },
                        ),
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              width: 190 * _pulseAnimation.value,
                              height: 190 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: provider.isConnected
                                    ? Colors.green.withValues(alpha: 0.08)
                                    : Colors.cyan.withValues(alpha: 0.08),
                              ),
                            );
                          },
                        ),
                        
                        // Button body
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E1E2F),
                            boxShadow: [
                              BoxShadow(
                                color: provider.isConnected
                                    ? Colors.greenAccent.withValues(alpha: 0.4)
                                    : provider.vpnState == 'CONNECTING'
                                        ? Colors.orangeAccent.withValues(alpha: 0.4)
                                        : Colors.cyanAccent.withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                            border: Border.all(
                              color: provider.isConnected
                                  ? Colors.greenAccent
                                  : provider.vpnState == 'CONNECTING'
                                      ? Colors.orangeAccent
                                      : Colors.cyanAccent,
                              width: 3,
                            ),
                          ),
                          child: Icon(
                            Icons.power_settings_new,
                            size: 64,
                            color: provider.isConnected
                                ? Colors.greenAccent
                                : provider.vpnState == 'CONNECTING'
                                    ? Colors.orangeAccent
                                    : Colors.cyanAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Protocol and secure details card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161626),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoColumn("ПРОТОКОЛ", "VLESS REALITY"),
                        Container(
                          height: 32,
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        _buildInfoColumn(
                          "СТАТУС",
                          provider.vpnState == 'CONNECTED' ? "АКТИВЕН" : "ОЖИДАНИЕ",
                          color: provider.isConnected ? Colors.greenAccent : Colors.cyanAccent,
                        ),
                      ],
                    ),
                  ),

                  // Location picker card
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ServersScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2F),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "ВЫБРАННЫЙ СЕРВЕР",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  provider.selectedServer?.name ?? "Поиск локации...",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoColumn(String label, String value, {Color color = Colors.white}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
