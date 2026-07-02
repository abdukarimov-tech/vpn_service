import 'package:client/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showInfoDialog(BuildContext context, String title, String content, String closeText) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            content,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                closeText,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          settings.translate('settings'),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Theme Tile
          _buildSettingsSection(
            settings.translate('theme'),
            [
              _buildSettingsCard(
                isDark: isDark,
                child: SwitchListTile(
                  activeThumbColor: accentColor,
                  activeTrackColor: accentColorMuted.withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                  value: settings.isDarkMode,
                  onChanged: (value) => settings.toggleTheme(value),
                  title: Text(
                    settings.translate('theme'),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    settings.isDarkMode ? settings.translate('dark') : settings.translate('light'),
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  secondary: Icon(
                    settings.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Language Tile
          _buildSettingsSection(
            settings.translate('language'),
            [
              _buildSettingsCard(
                isDark: isDark,
                child: ListTile(
                  leading: Icon(Icons.language_outlined, color: accentColor),
                  title: Text(
                    settings.translate('language'),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: accentColor.withValues(alpha: 0.2),
                      selectedForegroundColor: accentColor,
                      foregroundColor: isDark ? Colors.white70 : Colors.black54,
                    ),
                    segments: <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'ru',
                        label: Text(settings.translate('russian')),
                      ),
                      ButtonSegment<String>(
                        value: 'en',
                        label: Text(settings.translate('english')),
                      ),
                    ],
                    selected: {settings.languageCode},
                    onSelectionChanged: (Set<String> newSelection) {
                      settings.setLanguage(newSelection.first);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // About & Privacy Policy Tiles
          _buildSettingsSection(
            settings.translate('about'),
            [
              _buildSettingsCard(
                isDark: isDark,
                child: ListTile(
                  leading: Icon(Icons.info_outline, color: accentColor),
                  title: Text(
                    settings.translate('about'),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                  onTap: () => _showInfoDialog(
                    context,
                    settings.translate('about'),
                    settings.translate('about_text'),
                    settings.translate('close'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsCard(
                isDark: isDark,
                child: ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: accentColor),
                  title: Text(
                    settings.translate('privacy_policy'),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                  onTap: () => _showInfoDialog(
                    context,
                    settings.translate('privacy_policy'),
                    settings.translate('privacy_text'),
                    settings.translate('close'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSettingsCard({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161626) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}
