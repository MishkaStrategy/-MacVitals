# MacVitals

<p align="center">
  <strong>Нативный монитор состояния Apple Silicon Mac в строке меню macOS</strong>
</p>

<p align="center">
  <code>Swift 6</code> · <code>SwiftUI + AppKit</code> · <code>macOS 13+</code> · <code>ARM64</code> · <code>Локальная обработка</code>
</p>

<p align="center">
  <strong>Русский</strong> · <a href="README_EN.md">English</a>
</p>

<p align="center">
  <a href="docs/screenshots/status-bar-overview.png">
    <img src="./docs/screenshots/status-bar-overview.png" alt="Главный интерфейс MacVitals — строка меню и обзор показателей" width="900">
  </a>
</p>

<p align="center">
  <sub>Настоящий интерфейс MacVitals: элемент в строке меню и раскрытый обзор системных показателей.</sub>
</p>

MacVitals показывает состояние Mac без отдельной панели, аккаунта или облачного сервиса. Основные показатели всегда доступны в строке меню, а по нажатию открывается компактный обзор CPU, памяти, питания, температур, процессов и вентиляторов.

> **Статус:** MacVitals v1 находится в `main` и проходит предрелизную проверку. Текущая сборка unsigned. Developer ID signing, notarization и публичный релиз пока не выполнялись.

## Возможности

- загрузка CPU на основе системных Mach-счётчиков;
- использование памяти и нативный `memory pressure` macOS;
- заряд, состояние зарядки и здоровье батареи;
- сведения об адаптере и доступные показатели системной мощности;
- температура батареи и процессора, когда датчики доступны;
- модель и возможности Metal GPU без выдуманных значений загрузки;
- текущие, минимальные, целевые и максимальные обороты вентиляторов в read-only режиме;
- процессы с наибольшим потреблением ресурсов;
- ограниченная локальная история показателей;
- локальные уведомления с cooldown;
- русский и английский интерфейс;
- светлая, тёмная, двухцветная и многоцветная темы;
- отсутствие аккаунтов, аналитики, рекламы и фоновой отправки данных.

## Реальные изображения программы

Скриншоты ниже сняты непосредственно с работающего приложения XCTest-сценарием на macOS ARM64. Это не макеты и не концепт-рендеры.

### Основные настройки

<p align="center">
  <a href="docs/screenshots/preferences-general.png">
    <img src="./docs/screenshots/preferences-general.png" alt="Основные настройки MacVitals" width="900">
  </a>
</p>

### Настройка строки меню

<p align="center">
  <a href="docs/screenshots/preferences-menu-bar.png">
    <img src="./docs/screenshots/preferences-menu-bar.png" alt="Настройка показателей строки меню MacVitals" width="900">
  </a>
</p>

### Вентиляторы и безопасность

<p align="center">
  <a href="docs/screenshots/preferences-fans.png">
    <img src="./docs/screenshots/preferences-fans.png" alt="Мониторинг вентиляторов и настройки безопасности MacVitals" width="900">
  </a>
</p>

### Диагностика

<p align="center">
  <a href="docs/screenshots/preferences-diagnostics.png">
    <img src="./docs/screenshots/preferences-diagnostics.png" alt="Диагностика MacVitals" width="900">
  </a>
</p>

Аппаратно-зависимые значения на этих снимках относятся к CI-runner. Поэтому батарея, адаптер, температуры или вентиляторы могут отображаться как недоступные. Сценарий воспроизводимого захвата находится в [`.github/workflows/readme-screenshots.yml`](.github/workflows/readme-screenshots.yml).

## Поддерживаемая платформа

| Компонент | Требование |
|---|---|
| Процессор | Только Apple Silicon (`arm64`) |
| macOS | 13 Ventura и новее |
| Xcode | 16 и новее |
| Язык | Swift 6 |
| Интерфейс | SwiftUI + AppKit |

Intel (`x86_64`) и universal release-сборки намеренно отклоняются проверкой.

## Быстрый запуск из исходников

```bash
git clone https://github.com/MishkaStrategy/-MacVitals.git
cd -- -MacVitals
git switch main
make bootstrap
open MacVitals.xcodeproj
```

Проверка инструментов и тесты:

```bash
make validate-tooling
make test
```

Создание локального unsigned-пакета:

```bash
make package VERSION=0.0.0
```

В `dist/` создаются ZIP, DMG, контрольные суммы и сведения о происхождении сборки.

## Приватность и безопасность

Все показатели обрабатываются локально. MacVitals не выполняет сетевых запросов и не содержит аккаунтов, аналитики, телеметрии, рекламы или облачного backend.

Диагностические данные формируются без имён пользователей, домашних путей, серийных номеров, Apple ID, пользовательских документов и сетевой информации.

Unsigned-сборки используют вентиляторы только для read-only мониторинга. Регистрация privileged helper и изменение физических оборотов не заявляются.

Подробнее: [PRIVACY.md](PRIVACY.md).

## Проверка проекта

Автоматические и физические сценарии охватывают:

- форматирование и генерацию Xcode-проекта;
- нативную ARM64-сборку и тесты;
- запуск упакованного приложения;
- проверку ZIP и DMG;
- иконку, локализации, контрольные суммы и provenance;
- accessibility smoke на русском и английском;
- захват реального status item, popover и окон настроек;
- read-only проверку данных вентиляторов;
- direct-session стабильность и сбор Instruments.

До публичного релиза остаются Developer ID signing, notarization, Gatekeeper-проверка, финальный ручной аудит интерфейса и отдельное разрешение на публикацию.

## Документация

- [English README](README_EN.md)
- [Архитектура](ARCHITECTURE.md)
- [Приватность](PRIVACY.md)
- [Модель питания](docs/POWER_MODEL.md)
- [Совместимость датчиков](docs/SENSOR_COMPATIBILITY.md)
- [Performance evidence](docs/PERFORMANCE.md)
- [Build provenance](docs/BUILD_PROVENANCE.md)
- [Процесс релиза](docs/RELEASE.md)
