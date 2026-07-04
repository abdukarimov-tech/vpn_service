# iOS VPN (sing-box) — настройка Network Extension в Xcode

Android работает на `flutter_v2ray` без изменений. iOS использует вендоренный
плагин `sing_box` (в `client/plugins/sing_box`) с ядром sing-box, собранным в
`Libbox.xcframework`. Ядро запускается в **Network Extension (Packet Tunnel)** —
этот таргет нужно создать в Xcode вручную (один раз).

Идентификаторы (уже зашиты в код, менять не нужно):
- Bundle id приложения: `dev.rudnowski.freevpn`
- Bundle id расширения: `dev.rudnowski.freevpn.extension`  ← ровно так
- App Group: `group.dev.rudnowski.freevpn`  ← на обоих таргетах

---

## 0. Подготовка (терминал)

```bash
cd client
# Собрать ядро sing-box (~270MB, не в git). Нужны Xcode и интернет, ~10 мин.
bash scripts/build_libbox_ios.sh
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Проверь, что появился `client/plugins/sing_box/ios/Frameworks/Libbox.xcframework`.

---

## 1. Подпись основного приложения (Runner)

Xcode → target **Runner** → вкладка **Signing & Capabilities**:
1. **Team** — выбери свой Apple Developer аккаунт, включи **Automatically manage signing**.
2. Нажми **+ Capability** → **App Groups** → добавь `group.dev.rudnowski.freevpn`.
3. Нажми **+ Capability** → **Network Extensions** → отметь **Packet Tunnel**.

(В репозитории уже лежит `Runner/Runner.entitlements` с нужными ключами — Xcode
может использовать его или создать свой; главное, чтобы App Group и Network
Extensions были включены.)

---

## 2. Создание таргета расширения

1. **File → New → Target… → Network Extension** (категория iOS). Если такого
   шаблона нет, выбери **Packet Tunnel Provider**.
2. Параметры:
   - Product Name: **SingBoxExtension**
   - Language: **Swift**
   - Team: тот же, что у Runner
3. Xcode спросит «Activate scheme?» — можно **Cancel** (схема расширения не нужна).
4. Xcode создаст папку `SingBoxExtension/` со своим `PacketTunnelProvider.swift`
   и `Info.plist`. Их мы заменим (шаги 3–4).

Убедись, что **Bundle Identifier** нового таргета =
`dev.rudnowski.freevpn.extension` (General → Identity). И **Minimum Deployments = iOS 15.0**.

---

## 3. Исходники ядра в расширение

Ядро (класс `ExtensionProvider`) лежит в плагине. Добавим его файлы в таргет расширения:

1. В навигаторе проекта right-click на проекте → **Add Files to "Runner"…**
2. Выбери папку `plugins/sing_box/ios/Classes` (кнопка **Options**: сними
   «Copy items if needed», выбери **Create groups**).
3. В диалоге **Add to targets** отметь **только SingBoxExtension** (Runner уже
   получает эти файлы через CocoaPods — ему повторно не нужно).
4. После добавления найди в `Classes` файл **`SingBoxPlugin.swift`** → в
   инспекторе (File Inspector, справа) **сними** галку Target Membership
   `SingBoxExtension` (он импортирует Flutter и в расширении не нужен).

> Итог: в таргет `SingBoxExtension` входят все файлы `Classes/**` **кроме**
> `SingBoxPlugin.swift`.

Удали созданный Apple файл `SingBoxExtension/PacketTunnelProvider.swift`
(**Move to Trash**) — принципиальным классом будет `ExtensionProvider` из плагина.

---

## 4. Framework, Info.plist и entitlements расширения

1. **Libbox.xcframework в расширение:** target **SingBoxExtension** → **General**
   → **Frameworks and Libraries** → **+** → **Add Other… → Add Files…** →
   выбери `plugins/sing_box/ios/Frameworks/Libbox.xcframework`. Поставь
   **Embed & Sign**.
2. **Info.plist:** замени содержимое сгенерированного
   `SingBoxExtension/Info.plist` на файл из репозитория
   `ios/SingBoxExtension/Info.plist` (в нём уже прописан
   `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ExtensionProvider` и
   точка расширения `com.apple.networkextension.packet-tunnel`).
   Либо вручную впиши эти ключи в существующий Info.plist.
3. **Signing & Capabilities** таргета **SingBoxExtension**:
   - Team — тот же.
   - **+ Capability → App Groups** → `group.dev.rudnowski.freevpn`.
   - **+ Capability → Network Extensions** → **Packet Tunnel**.
   - (Готовый `ios/SingBoxExtension/SingBoxExtension.entitlements` содержит те же ключи.)

---

## 5. Встраивание расширения в приложение

Target **Runner** → **General** → **Frameworks, Libraries, and Embedded
Content** → убедись, что **SingBoxExtension.appex** присутствует и стоит
**Embed Without Signing** (Xcode обычно добавляет его автоматически как
зависимость при создании таргета).

---

## 6. Сборка и запуск на iPad

1. Подключи iPad, выбери его как устройство.
2. Схема **Runner** → **Run**.
3. При первом подключении iOS покажет системный диалог **«"Barys VPN" хочет
   добавить конфигурации VPN»** — разреши. Плагин ставит профиль и запускает
   тоннель автоматически при нажатии Connect.
4. Проверь выход в интернет через VPN (например, whatismyipaddress).

---

## Возможные проблемы

- **"Unable to resolve module 'Libbox'" в расширении** — не прилинкован
  `Libbox.xcframework` к таргету SingBoxExtension (шаг 4.1).
- **"Missing entitlement" / VPN не стартует** — не совпадает App Group или
  bundle id расширения ≠ `dev.rudnowski.freevpn.extension`.
- **Provisioning error** — включи Automatically manage signing на обоих
  таргетах; Xcode сам создаст профили с NE-правами (аккаунт должен быть платным).
- **Тоннель падает по памяти** — iOS ограничивает память NE. Если будет
  проблема, пересобрать ядро с уменьшённым набором тегов (см.
  `scripts/build_libbox_ios.sh`, флаги сборки).
- **Симулятор** — VPN в симуляторе не работает, только реальное устройство.
