import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  String _languageCode = 'ru';

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _languageCode = prefs.getString('languageCode') ?? 'ru';
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (code == 'ru' || code == 'en') {
      _languageCode = code;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('languageCode', code);
      notifyListeners();
    }
  }

  // Translation helper
  String translate(String key) {
    return _localizedValues[_languageCode]?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      'title': 'FREE VPN',
      'secured': 'ЗАЩИЩЕНО',
      'connecting': 'ПОДКЛЮЧЕНИЕ...',
      'disconnected': 'ОТКЛЮЧЕНО',
      'protocol': 'ПРОТОКОЛ',
      'status': 'СТАТУС',
      'active': 'АКТИВЕН',
      'idle': 'ОЖИДАНИЕ',
      'selected_server': 'ВЫБРАННЫЙ СЕРВЕР',
      'locating_server': 'Поиск локации...',
      'vpn_locations': 'Локации VPN',
      'no_servers': 'Нет доступных серверов',
      'refresh': 'Обновить',
      'ad_warning': 'Необходимо досмотреть видео для подключения к VPN',
      'settings': 'Настройки',
      'theme': 'Тема оформления',
      'language': 'Язык интерфейса',
      'about': 'О приложении',
      'privacy_policy': 'Политика конфиденциальности',
      'about_text': 'Бесплатное и безопасное VPN-приложение с использованием передового протокола VLESS Reality. Создано для защиты вашей конфиденциальности в Интернете.',
      'privacy_text': 'Политика конфиденциальности\n\n1. Безопасность данных: Мы не собираем, не храним и не передаем третьим лицам ваши личные данные, логи активности или историю посещений. Все данные сессии передаются в зашифрованном виде.\n\n2. Реклама и аналитика: Для показа рекламы в приложении интегрирована служба Google AdMob. Google AdMob может собирать идентификаторы устройств (Advertising ID), данные об использовании приложения и примерную геолокацию для персонализации и оптимизации рекламы.',
      'close': 'Закрыть',
      'light': 'Светлая',
      'dark': 'Темная',
      'russian': 'Русский',
      'english': 'English',
    },
    'en': {
      'title': 'FREE VPN',
      'secured': 'SECURED',
      'connecting': 'CONNECTING...',
      'disconnected': 'DISCONNECTED',
      'protocol': 'PROTOCOL',
      'status': 'STATUS',
      'active': 'ACTIVE',
      'idle': 'IDLE',
      'selected_server': 'SELECTED SERVER',
      'locating_server': 'Locating server...',
      'vpn_locations': 'VPN Locations',
      'no_servers': 'No servers available',
      'refresh': 'Refresh',
      'ad_warning': 'You need to watch the video to connect to VPN',
      'settings': 'Settings',
      'theme': 'Theme Mode',
      'language': 'Language',
      'about': 'About App',
      'privacy_policy': 'Privacy Policy',
      'about_text': 'A free and secure VPN application utilizing the advanced VLESS Reality protocol. Designed to protect your online privacy.',
      'privacy_text': 'Privacy Policy\n\n1. Data Security: We do not collect, store, or share your personal data, activity logs, or browsing history with third parties. All session data is transmitted in encrypted form.\n\n2. Advertising and Analytics: We use Google AdMob to serve advertisements. Google AdMob may collect device identifiers (Advertising ID), app usage metrics, and approximate location data to show and optimize relevant ads.',
      'close': 'Close',
      'light': 'Light',
      'dark': 'Dark',
      'russian': 'Russian',
      'english': 'English',
    }
  };
}
