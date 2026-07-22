# MacVitals

MacVitals — лёгкая нативная утилита для строки меню macOS, которая показывает загрузку CPU и памяти, системный memory pressure, состояние батареи, параметры адаптера и направление потока энергии. Она помогает понять, хватает ли мощности зарядного устройства при текущей нагрузке MacBook.

Все данные обрабатываются локально. В приложении нет аккаунтов, рекламы, аналитики, телеметрии, облачного backend, `sudo` и управления зарядкой.

## Текущий статус проверки

Автоматические macOS workflow уже подтверждают:

- SwiftFormat и генерацию Xcode-проекта;
- нативные сборки на hosted arm64 и Intel x86_64;
- unit-тесты и provider/hardware-smoke выборку системных метрик;
- запуск настоящего упакованного Release-приложения на обеих архитектурах;
- короткий runtime guardrail по CPU, RSS, периодичности сэмплов и числу потоков;
- universal unsigned Release archive;
- создание и проверку ZIP и DMG;
- совпадение содержимого приложений в ZIP и DMG;
- EN/RU ресурсы и двуязычный UI smoke;
- SHA-256 контрольные суммы;
- `BUILD_MANIFEST.json` с версией, commit, Xcode, архитектурами и состоянием подписи/нотаризации.

Hosted Intel CI завершён, но он не заменяет физическую проверку Intel MacBook с батареей и адаптерами. Не завершены Apple Developer ID signing, notarization, Instruments-замеры, многочасовая стабильность и полная проверка на физических Mac. PR поэтому остаётся черновым.

## Важные ограничения

- Системная загрузка GPU не подделывается. При отсутствии надёжного публичного источника интерфейс показывает, что метрика недоступна.
- Номинальная мощность адаптера не выдаётся за фактическое потребление.
- Расширенные поля батареи из IORegistry проверяются во время выполнения и помечаются как экспериментальные.
- CI-пакеты явно помечены как unsigned и not notarized.
- Hosted runtime-цифры являются только регрессионным свидетельством конкретных runner-ов, а не обещанием производительности на всех Mac.
- Реальные скриншоты, energy/wakeup и итоговые performance-цифры публикуются только после проверки на физическом оборудовании.

## Сборка

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
- физический Intel Mac для сохраняемых sensor-claims либо явное сужение поддержки;
- Instruments и многочасовой stability run;
- финальные скриншоты, accessibility review и production icon.

Подробности: [архитектура](ARCHITECTURE.md), [модель питания](docs/POWER_MODEL.md), [совместимость датчиков](docs/SENSOR_COMPATIBILITY.md), [provenance сборки](docs/BUILD_PROVENANCE.md), [процесс релиза](docs/RELEASE.md), [приватность](PRIVACY.md).