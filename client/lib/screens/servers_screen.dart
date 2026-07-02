import 'package:client/models/server_model.dart';
import 'package:client/providers/vpn_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VpnProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Локации VPN",
          style: TextStyle(
            color: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Нет доступных серверов",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => provider.init(),
                    icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                    label: const Text(
                      "Обновить",
                      style: TextStyle(color: Colors.cyanAccent),
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
                      color: isSelected ? const Color(0xFF1E1E2F) : const Color(0xFF161626),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.05),
                        width: 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.cyanAccent.withValues(alpha: 0.1),
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
                                ? Colors.cyanAccent.withValues(alpha: 0.15) 
                                : Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.dns_outlined,
                            color: isSelected ? Colors.cyanAccent : Colors.white70,
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "IP: ${server.ip}",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Checkmark/Selection indicator
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.cyanAccent,
                          )
                        else
                          Icon(
                            Icons.circle_outlined,
                            color: Colors.white.withValues(alpha: 0.2),
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
