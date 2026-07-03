import 'package:client/providers/settings_provider.dart';
import 'package:client/providers/vpn_provider.dart';
import 'package:client/screens/servers_screen.dart';
import 'package:client/screens/settings_screen.dart';
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
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (provider.isConnected) {
      // Disconnect directly
      await provider.disconnect();
      _pulseController.stop();
    } else if (provider.vpnState == 'DISCONNECTED' || provider.vpnState == 'DENIED') {
      // Ask for the VPN permission first so its system dialog doesn't collide
      // with the full-screen ad.
      final hasPermission = await provider.requestVpnPermission();
      if (!mounted) return;
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(settings.translate('ad_warning')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      // Tell the user we're connecting in the background while they watch the ad.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(settings.translate('connecting_ad_message')),
          duration: const Duration(seconds: 4),
        ),
      );

      // Start connecting and show the ad at the same time.
      final connectFuture = provider.connect();
      await AdService().showAd(context);
      await connectFuture;
      if (!mounted) return;
      if (provider.isConnected) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VpnProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final theme = Theme.of(context);
    final isDark = settings.isDarkMode;
    
    // Indigo/Blue for light theme, Cyan for dark theme
    final accentColor = isDark ? Colors.cyanAccent : const Color(0xFF2563EB);
    final accentColorMuted = isDark ? Colors.cyan : const Color(0xFF3B82F6);

    // Keep pulse animation updated based on status
    if (provider.isConnected && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!provider.isConnected && _pulseController.isAnimating) {
      _pulseController.stop();
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
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
            Text(
              settings.translate('title'),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
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
                            ? settings.translate('secured')
                            : provider.vpnState == 'CONNECTING'
                                ? settings.translate('connecting')
                                : settings.translate('disconnected'),
                        style: TextStyle(
                          color: provider.isConnected 
                              ? Colors.greenAccent 
                              : (isDark ? Colors.white70 : Colors.black54),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.vpnDuration,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
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
                                    : accentColorMuted.withValues(alpha: 0.04),
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
                                    : accentColorMuted.withValues(alpha: 0.08),
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
                            color: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: provider.isConnected
                                    ? Colors.greenAccent.withValues(alpha: 0.4)
                                    : provider.vpnState == 'CONNECTING'
                                        ? Colors.orangeAccent.withValues(alpha: 0.4)
                                        : accentColor.withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                            border: Border.all(
                              color: provider.isConnected
                                  ? Colors.greenAccent
                                  : provider.vpnState == 'CONNECTING'
                                      ? Colors.orangeAccent
                                      : accentColor,
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
                                    : accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Protocol and secure details card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark 
                            ? Colors.white.withValues(alpha: 0.05) 
                            : Colors.black.withValues(alpha: 0.05),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoColumn(
                          context,
                          settings.translate('protocol'), 
                          "VLESS REALITY",
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        Container(
                          height: 32,
                          width: 1,
                          color: isDark 
                              ? Colors.white.withValues(alpha: 0.1) 
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                        _buildInfoColumn(
                          context,
                          settings.translate('status'),
                          provider.vpnState == 'CONNECTED' 
                              ? settings.translate('active') 
                              : settings.translate('idle'),
                          color: provider.isConnected ? Colors.greenAccent : accentColor,
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
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withValues(alpha: 0.05) 
                              : Colors.black.withValues(alpha: 0.05),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settings.translate('selected_server'),
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  provider.selectedServer?.name ?? settings.translate('locating_server'),
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: isDark ? Colors.white54 : Colors.black54,
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

  Widget _buildInfoColumn(BuildContext context, String label, String value, {required Color color}) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = settings.isDarkMode;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
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
