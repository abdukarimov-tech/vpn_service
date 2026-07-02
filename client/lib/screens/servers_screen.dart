import 'package:client/models/server_model.dart';
import 'package:client/providers/vpn_provider.dart';
import 'package:client/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VpnProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final theme = Theme.of(context);
    final isDark = settings.isDarkMode;

    final accentColor = isDark ? Colors.cyanAccent : const Color(0xFF2563EB);
    final accentColorMuted = isDark ? Colors.cyan : const Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          settings.translate('vpn_locations'),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: provider.servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 64,
                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    settings.translate('no_servers'),
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => provider.init(),
                    icon: Icon(Icons.refresh, color: accentColor),
                    label: Text(
                      settings.translate('refresh'),
                      style: TextStyle(color: accentColor),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              itemCount: provider.servers.length,
              itemBuilder: (context, index) {
                final ServerModel server = provider.servers[index];
                final isSelected = provider.selectedServer?.name == server.name;

                return GestureDetector(
                  onTap: () {
                    provider.selectServer(server);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? (isDark ? const Color(0xFF1E1E2F) : accentColorMuted.withValues(alpha: 0.1)) 
                          : theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected 
                            ? accentColor 
                            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                        width: 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.1),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        // Server flag/icon placeholder
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? accentColor.withValues(alpha: 0.15) 
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.dns_outlined,
                            color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Server Name and IP
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                server.name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "IP: ${server.ip}",
                                style: TextStyle(
                                  color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Checkmark/Selection indicator
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: accentColor,
                          )
                        else
                          Icon(
                            Icons.circle_outlined,
                            color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
