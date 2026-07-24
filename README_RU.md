# MacVitals

MacVitals — лёгкая нативная утилита для строки меню macOS на Apple Silicon, которая показывает загрузку CPU и памяти, системный memory pressure, состояние батареи, параметры адаптера и направление потока энергии. Она помогает понять, хватает ли мощности зарядного устройства при текущей нагрузке MacBook.

Все данные обрабатываются локально. В приложении нет аккаунтов, рекламы, аналитики, телеметрии, облачного backend, `sudo` и управления зарядкой.

## Поддерживаемая платформа

- Только Apple Silicon (`arm64`)
- macOS 13 и новее
- Сборки Intel (`x86_64`) намеренно не поддерживаются и отклоняются релизной проверкой

## Текущий статус проверки

Автоматический macOS workflow уже подтверждает:

- SwiftFormat и генерацию Xcode-проекта;
- нативную arm64-сборку;
- unit-тесты и provider/hardware-smoke выборку системных метрик;
- запуск настоящего упакованного Release-приложения на Apple Silicon;
- короткий runtime guardrail по CPU, RSS, периодичности сэмплов и числу потоков;
- arm64-only unsigned Release archive;
- создание и проверку ZIP и DMG;
- production app icon и его совпадение в ZIP/DMG;
- совпадение содержимого приложений в ZIP и DMG;
- EN/RU ресурсы и двуязычный accessibility smoke всех пяти вкладок настроек;
- SHA-256 контрольные суммы;
- `BUILD_MANIFEST.json` с версией, commit, Xcode, архитектурой и состоянием подписи/нотаризации.

Intel workflow удалён, а universal/x86_64-пакеты теперь считаются ошибкой. Не завершены Apple Developer ID signing, notarization, Instruments-замеры, многочасовая стабильность и полная проверка на физических Apple Silicon Mac. PR поэтому остаётся черновым.

## Важные ограничения

- Системная загрузка GPU не подделывается. При отсутствии надёжного публичного источника интерфейс показывает, что метрика недоступна.
- Номинальная мощность адаптера не выдаётся за фактическое потребление.
- Расширенные поля батареи из IORegistry проверяются во время выполнения и помечаются как экспериментальные.
- CI-пакеты явно помечены как unsigned и not notarized.
- Hosted runtime-цифры являются только регрессионным свидетельством конкретного runner, а не обещанием производительности на всех Apple Silicon Mac.
- Реальные скриншоты, energy/wakeup и итоговые performance-цифры публикуются только после проверки на физическом оборудовании.

## Сборка

Требования: Apple Silicon Mac, macOS 13+, Xcode 16+, Homebrew.

```bash
git clone https://github.com/mishkacher/-MacVitals.git
cd -- -MacVitals
make bootstrap
open MacVitals.xcodeproj
```

Проверка инструментов и тесты:

```bash
make validate-tooling
make test
```

Локальный unsigned-пакет:

```bash
make package VERSION=0.0.0
```

В `dist/` создаются:

- `MacVitals-<version>.zip`
- `MacVitals-<version>.dmg`
- `SHA256SUMS.txt`
- `BUILD_STATUS.txt`
- `BUILD_MANIFEST.json`

Verifier требует единственную архитектуру `arm64` и отклоняет universal либо x86_64 executable.

Короткий runtime guardrail для упакованного приложения:

```bash
make runtime-smoke VERSION=0.0.0
```

Более длинный сбор CPU/RSS/VSZ/потоков для уже запущенного приложения:

```bash
make collect-runtime RUNTIME_DURATION=900 RUNTIME_INTERVAL=2
```

Эти замеры не заменяют Instruments, проверку Energy Impact, wakeups, температуры и реальной автономности.

## Оставшиеся релизные проверки

- Developer ID signing, notarization, stapling и Gatekeeper с настоящими Apple-учётными данными;
- физические сценарии батареи и адаптеров на Apple Silicon MacBook;
- Instruments и многочасовой stability run;
- финальные скриншоты, VoiceOver review и визуальная проверка на физическом Apple Silicon оборудовании.

Подробности: [архитектура](ARCHITECTURE.md), [иконка приложения](docs/APP_ICON.md), [модель питания](docs/POWER_MODEL.md), [совместимость датчиков](docs/SENSOR_COMPATIBILITY.md), [provenance сборки](docs/BUILD_PROVENANCE.md), [процесс релиза](docs/RELEASE.md), [приватность](PRIVACY.md).
