<div align="center">
  <img src="assets/readme-banner.svg" alt="Mint Bookshelf" width="100%">
  <h1>Mint Bookshelf</h1>
  <p><strong>Нативное приложение macOS для вашей библиотеки книг и Kindle по USB.</strong></p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.ru.md">Русский</a> ·
    <a href="README.es.md">Español</a> ·
    <a href="README.pt.md">Português</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.fr.md">Français</a>
  </p>

  <p>
    <a href="../../releases"><img alt="Релизы" src="https://img.shields.io/badge/releases-GitHub-86C9BB?style=flat-square"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0A1014?style=flat-square&logo=apple&logoColor=white">
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-0A1014?style=flat-square&logo=swift&logoColor=F05138">
    <img alt="Go" src="https://img.shields.io/badge/Go-core-0A1014?style=flat-square&logo=go&logoColor=00ADD8">
    <img alt="MTP" src="https://img.shields.io/badge/Kindle-MTP-86C9BB?style=flat-square">
    <img alt="MIT" src="https://img.shields.io/badge/license-MIT-97A7AC?style=flat-square">
  </p>
</div>

> **Локальная библиотека. Прямой доступ по USB. Без облака и лишнего.**
>
> Mint Bookshelf объединяет книги, Kindle и повседневную работу с файлами в одном аккуратном приложении macOS.

## Возможности

| Библиотека | Kindle | Файлы |
| --- | --- | --- |
| Обложки, поиск, описание книги и сортировка по названию, автору или дате добавления. | Дерево папок MTP, загрузка, скачивание, перемещение, копирование, переименование и удаление. | Локальный браузер в стиле Finder: копирование, вставка, перетаскивание и фоновые операции. |

| Конвертация | Внешний вид | Удобство |
| --- | --- | --- |
| Конвертация через Calibre с прогрессом и отменой. | Тёмная и светлая темы, шесть языков интерфейса, нативное поведение macOS. | Без лишних панелей: контекстные меню, сочетания клавиш и чистое разделение на список и описание. |

## Что умеет приложение

- Сканирует только выбранную папку и запоминает её между запусками.
- Извлекает обложки из EPUB, MOBI, AZW, AZW3, PDF и FB2; при отсутствии создаёт аккуратную обложку.
- Ищет по названию, автору и серии; сортирует по названию, автору и дате добавления.
- Показывает Kindle как дерево папок и передаёт файлы с прогрессом по байтам.
- Конвертирует книги через Calibre и показывает задачи в списке активности.
- Позволяет переключать **английский, русский, испанский, португальский, китайский и французский** в любое время.

## Поддерживаемые Kindle

Приложение работает с **современными MTP-Kindle** через libmtp.

- Проверено на **Kindle Scribe** и актуальных моделях 2025 года.
- Ожидается поддержка Kindle Scribe, Paperwhite 5/Signature, Kindle 11-го поколения и новее, Colorsoft и моделей 2024–2025.
- **Не поддерживаются:** старые Kindle с USB mass storage, включая Kindle Paperwhite 2 (DP75SDI, 2013–2014).

> Одновременно должен быть открыт только один MTP-сеанс. Закройте другие MTP-программы перед работой с Kindle.

## Установка

1. Откройте страницу [Releases](../../releases).
2. Скачайте `MintBookshelf-<версия>.dmg`.
3. Откройте DMG и перетащите **Mint Bookshelf** в **Applications**.

Текущая сборка предназначена для **Apple Silicon** и подписана ad-hoc. Если macOS блокирует первый запуск, нажмите на приложение правой кнопкой и выберите **Открыть**.

Для публичного распространения без предупреждений Gatekeeper используйте Developer ID и notarization. См. `docs/BUILD.md`.

## Сборка

Требуются macOS 14+, Xcode, Go, Homebrew, `pkg-config`, `libmtp` и `libusb`.

```sh
brew install pkg-config libmtp libusb
make check-deps
make package
make dmg
```

Готовое приложение появится в `macos/Mint Bookshelf.app`, DMG — в `build/MintBookshelf.dmg`.

## Релизы

Релизы собираются в GitHub Actions:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Workflow **Release** запускает тесты Go и Swift, подставляет версию, собирает DMG, проверяет его, создаёт SHA-256 и публикует оба файла во вкладке **Releases**. Можно также запустить вручную: **Actions → Release → Run workflow**.

## Архитектура

- **SwiftUI**, Swift 6, macOS 14+
- **Ядро на Go** в `libkindlecore.dylib`, C ABI и JSON
- **libmtp/libusb** для доступа к Kindle
- **SQLite** для библиотеки и истории операций
- **Calibre CLI** для необязательной конвертации

## Тесты

```sh
go test ./...
make test-race
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macos
```

## Локализация

Интерфейс полностью переведён на английский, русский, испанский, португальский, упрощённый китайский и французский. Язык выбирается в правом верхнем меню и запоминается; по умолчанию используется системный.

Добавить язык просто:

1. Добавьте `case` и название в `AppLanguage` в `macos/Sources/MintBookshelf/Localization.swift`.
2. Создайте один словарь, например `Localization+German.swift`.
3. Зарегистрируйте его в `L10n.tables`.

Все строки интерфейса, статусы, счётчики и ошибки используют общий API `L10n`.

## Примечания

- Поддерживаются только современные MTP-Kindle; USB mass storage не поддерживается.
- Можно выбирать несколько устройств Amazon; обнаружение и переподключение опрашиваются.
- Удаление с устройства необратимо и требует подтверждения.
- Приложение держит один MTP-сеанс на всё время работы.
- `docs/` содержит локальные заметки и документацию по сборке.

## Лицензия

MIT. См. [LICENSE](LICENSE).
