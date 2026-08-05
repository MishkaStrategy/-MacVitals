<div align="center">

# MacVitals

### Нативный монитор состояния Mac в строке меню и вокруг выреза камеры

CPU, память, батарея, питание, температуры, процессы, данные вентиляторов, настраиваемый status bar и опциональная HUD-панель — локально на Apple Silicon.

<p>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111111?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-111111?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2ea44f">
  <img alt="Без телеметрии" src="https://img.shields.io/badge/телеметрия-нет-2563eb">
</p>

[English](README.md) · **Русский** · [Архитектура](ARCHITECTURE.md) · [Приватность](PRIVACY.md)

</div>

<p align="center">
  <a href="docs/screenshots/status-bar-overview.png">
    <img src="docs/screenshots/status-bar-overview.png" alt="Реальный status bar и обзор MacVitals" width="640">
  </a>
</p>

> [!IMPORTANT]
> MacVitals v1 находится на предрелизной стадии. Текущая сборка для Apple Silicon остаётся unsigned. Developer ID signing, notarization, stapling, финальная accessibility-проверка и публичный релиз ещё не завершены.

## Что такое MacVitals

MacVitals — нативное приложение на SwiftUI и AppKit, которое держит важные показатели системы рядом и не требует аккаунта, браузерной панели или облачного сервиса.

Информация отображается в трёх связанных интерфейсах:

- компактный настраиваемый элемент в строке меню macOS;
- обзорный popover с карточками, историей, питанием и ресурсоёмкими процессами;
- опциональный контурный HUD вокруг выреза камеры с одним или двумя выбранными датчиками.

<table>
  <tr>
    <td width="25%" align="center"><strong>Нативно</strong><br><sub>Swift 6, SwiftUI и AppKit</sub></td>
    <td width="25%" align="center"><strong>Локально</strong><br><sub>Без аккаунтов, рекламы и телеметрии</sub></td>
    <td width="25%" align="center"><strong>Достоверно</strong><br><sub>Недоступные значения не выдумываются</sub></td>
    <td width="25%" align="center"><strong>Для Mac</strong><br><sub>Apple Silicon и macOS 13+</sub></td>
  </tr>
</table>

## Status bar и обзор

В строке меню можно выбрать состав и порядок метрик. По нажатию открывается настоящий обзор MacVitals с карточками CPU, памяти, GPU, батареи, температуры и вентиляторов, интерпретацией потока питания, короткой историей CPU и переходами к подробным экранам.

Изображение в начале README — прямой full-screen снимок работающего приложения, полученный XCTest. Это не макет и не сгенерированный концепт интерфейса.

## HUD-панель вокруг выреза

<p align="center">
  <a href="docs/screenshots/notch-hud.png">
    <img src="docs/screenshots/notch-hud.png" alt="Реальная HUD-панель MacVitals вокруг выреза камеры" width="1000">
  </a>
</p>

HUD использует одну прозрачную AppKit-панель `NSPanel` и рисует U-образный контур вокруг аппаратного выреза. Поддерживаются:

- один индикатор по всему контуру или два независимых индикатора по половинам;
- выбор отображаемых датчиков;
- подписи значений и названий датчиков;
- автоматический, системный или пользовательский цвет;
- пороги предупреждения и критического состояния;
- настройка толщины, ширины, прозрачности трека, свечения и анимации;
- безопасное скрытие HUD, когда достоверная геометрия выреза недоступна.

Снимок HUD создаётся настоящим рендерером приложения. На hosted Mac без физического выреза workflow включает предусмотренный программой режим имитации контура. Геометрия и поведение одной панели дополнительно проверены на физическом MacBook с вырезом.

## Системные показатели

| Область | Что показывает MacVitals |
|---|---|
| **CPU** | Загрузку по разнице системных Mach-счётчиков и ограниченную локальную историю |
| **Память** | RAM, swap и нативное состояние memory pressure macOS |
| **Батарея** | Заряд, состояние зарядки, здоровье и доступные расширенные поля |
| **Питание** | Номинальную и согласованную мощность адаптера отдельно от измеренного или вычисленного потребления |
| **Температуры** | Температуру батареи и процессора, когда доступен надёжный источник |
| **GPU** | Модель и возможности Metal; загрузку только при наличии достоверного провайдера |
| **Вентиляторы** | Доступные RPM, целевые и предельные значения и режим через AppleSMC |
| **Процессы** | Приложения и процессы с наибольшим текущим потреблением ресурсов |
| **История** | Ограниченные буферы в памяти с явными разрывами после сна и пробуждения |
| **Уведомления** | Локальные предупреждения с cooldown и явным запросом разрешения |
| **Диагностика** | Доступность провайдеров, сведения о выборке и обезличенный пакет поддержки |

## Реальные окна настроек

Все изображения ниже — прямые XCTest-снимки настоящего приложения.

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>Основные</strong><br>
      <sub>Интервал мониторинга, Dock, запуск при входе и состояние сеанса.</sub><br><br>
      <a href="docs/screenshots/preferences-general.png"><img src="docs/screenshots/preferences-general.png" alt="Реальные основные настройки MacVitals" width="100%"></a>
    </td>
    <td width="50%" valign="top">
      <strong>Строка меню</strong><br>
      <sub>Предпросмотр, профили и порядок отображаемых метрик.</sub><br><br>
      <a href="docs/screenshots/preferences-menu-bar.png"><img src="docs/screenshots/preferences-menu-bar.png" alt="Реальная настройка строки меню MacVitals" width="100%"></a>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>Вентиляторы и безопасность</strong><br>
      <sub>Доступная телеметрия и ограничения unsigned-сборки.</sub><br><br>
      <a href="docs/screenshots/preferences-fans.png"><img src="docs/screenshots/preferences-fans.png" alt="Реальный экран вентиляторов MacVitals" width="100%"></a>
    </td>
    <td width="50%" valign="top">
      <strong>Диагностика</strong><br>
      <sub>Доступность источников, версия и экспорт пакета поддержки.</sub><br><br>
      <a href="docs/screenshots/preferences-diagnostics.png"><img src="docs/screenshots/preferences-diagnostics.png" alt="Реальный экран диагностики MacVitals" width="100%"></a>
    </td>
  </tr>
</table>

Воспроизводимая реализация захвата находится в [`.github/workflows/readme-screenshots.yml`](.github/workflows/readme-screenshots.yml) и `MacVitalsUITests`.

## Принципы достоверности

1. **Не выдумывать отсутствующие значения.** Недоступная метрика остаётся недоступной.
2. **Разделять паспортные данные и измерения.** Мощность адаптера не выдаётся за текущее потребление Mac.
3. **Показывать происхождение оценки.** Прямые, вычисленные и экспериментальные значения различаются.
4. **Проверять возможности во время выполнения.** Аппаратно-зависимые провайдеры включаются только при поддержке.
5. **Безопасно отказывать.** HUD и связанные с вентиляторами пути не используют небезопасные скрытые fallback-механизмы.

## Поддерживаемая платформа

| Компонент | Требование |
|---|---|
| Архитектура | Только Apple Silicon (`arm64`) |
| macOS | 13 Ventura и новее |
| Xcode | 16 и новее |
| Swift | 6 со строгой concurrency-проверкой |
| Генерация проекта | XcodeGen |
| Лицензия | MIT |

Intel и universal release-сборки намеренно отклоняются проверками проекта.

## Сборка из исходников

```bash
git clone https://github.com/MishkaStrategy/-MacVitals.git
cd -- -MacVitals
git switch feature/macvitals-v1
make bootstrap
open MacVitals.xcodeproj
```

Основные команды:

```bash
make validate-tooling
make build
make test
make package VERSION=0.0.0
make runtime-smoke VERSION=0.0.0
```

Unsigned-пакет включает ZIP, DMG, контрольные суммы, `BUILD_STATUS.txt` и `BUILD_MANIFEST.json`.

## Приватность

MacVitals обрабатывает показатели локально и не содержит аккаунтов, аналитики, телеметрии, рекламы, облачного backend или автоматической отправки диагностики.

Пакет поддержки создаётся только по явному действию пользователя и не должен включать имя пользователя, домашние пути, серийные номера, Apple ID, личные файлы, сетевые сведения и стабильные персональные идентификаторы.

Подробнее: [PRIVACY.md](PRIVACY.md).

## Ограничения и безопасность

- macOS не предоставляет единый публичный API достоверной системной загрузки GPU для всех поддерживаемых Mac;
- доступность температур, питания, батареи и вентиляторов зависит от модели и версии macOS;
- расширенные поля батареи из IORegistry проверяются и считаются экспериментальными;
- unsigned-сборки сохраняют явные ограничения безопасности для вентиляторов;
- физическое управление вентиляторами не заявляется как готовая релизная функция;
- значения на hosted-снимках относятся к runner, а не ко всем Mac;
- signing, notarization, stapling и Gatekeeper-проверка на чистом Mac остаются незавершёнными.

## Статус проверки

Текущий пайплайн проверяет нативную ARM64-сборку и тесты, русский и английский интерфейс, unsigned-упаковку, контрольные суммы и provenance, runtime smoke, read-only данные вентиляторов, физические direct-session сценарии, геометрию выреза и работу HUD через одну панель.

До публичного релиза остаются финальная ручная UX/accessibility-проверка, Developer ID signing, notarization, Gatekeeper и отдельное разрешение на merge, тег и release.

## Документация

- [English README](README.md)
- [Архитектура](ARCHITECTURE.md)
- [Приватность](PRIVACY.md)
- [Модель питания](docs/POWER_MODEL.md)
- [Совместимость датчиков](docs/SENSOR_COMPATIBILITY.md)
- [Performance evidence](docs/PERFORMANCE.md)
- [Build provenance](docs/BUILD_PROVENANCE.md)
- [Процесс релиза](docs/RELEASE.md)

<div align="center">

**Понимайте состояние Mac, не отправляя его показатели наружу.**

Проект распространяется по [лицензии MIT](LICENSE).

</div>
