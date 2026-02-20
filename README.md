# LinkedIn Applications Tracker

Проект для обработки писем LinkedIn о вакансиях и работы с заявками в SQL/GUI.

## Что в репозитории

- `scripts/update_linkedin_applications.py`  
  Парсит `.txt` письма и обновляет markdown-файлы для Obsidian.
- `scripts/folder_shell_sql.py`  
  SQL-backed shell для просмотра иерархии файлов в терминале.
- `scripts/linkedin_applications_gui_sql.py`  
  Python GUI (PySide6) с SQLite, автоклассификацией и ручным управлением статусами.
- `LinkInJob/`  
  Нативное macOS-приложение (SwiftUI), работающее с тем же пайплайном и SQLite.

## Структура проекта

- `scripts/setup_rclone_drive.sh` — настройка `rclone` remote для Google Drive.
- `scripts/sync_drive_rclone.sh` — синхронизация TXT-архива из Google Drive.
- `scripts/setup_argos_runtime.sh` — установка локального Argos Translate runtime.
- `scripts/update_linkedin_applications.py` — обновление markdown-сводок.
- `scripts/folder_shell_sql.py` — SQL shell в терминале.
- `scripts/linkedin_applications_gui_sql.py` — Python GUI заявок.
- `LinkInJob/scripts/build_and_install_app.sh` — сборка и установка macOS app в `/Applications/LinkInJob.app`.

## Требования

- Python 3
- `PySide6` (для Python GUI):

```bash
python3 -m pip install PySide6
```

- Опционально: `rclone` (для sync с Google Drive)
- Для `LinkInJob` (SwiftUI): Xcode/Swift toolchain

## Основные пути (по умолчанию)

- TXT-архив писем:  
  `$HOME/Library/Application Support/DriveCVSync/LinkedIn Archive`
- SQLite БД заявок:  
  `$HOME/.local/share/linkedin_apps/applications.db`
- Лог последней синхронизации (LinkInJob):  
  `$HOME/Library/Application Support/LinkInJob/Logs/last_sync.log`

## Использование

### 1) Обновить Obsidian markdown из TXT писем

```bash
python3 scripts/update_linkedin_applications.py
```

Переопределить пути:

```bash
python3 scripts/update_linkedin_applications.py \
  --source-dir "/path/to/email-txt-files" \
  --target-file "/path/to/output.md"
```

### 2) SQL shell (терминал)

```bash
python3 scripts/folder_shell_sql.py
```

С кастомным source/DB:

```bash
python3 scripts/folder_shell_sql.py \
  "/path/to/source-folder" \
  --db "/path/to/hierarchy.db" \
  --sync-first
```

### 3) Python GUI заявок (PySide6)

```bash
python3 scripts/linkedin_applications_gui_sql.py \
  --source-dir "$HOME/Library/Application Support/DriveCVSync/LinkedIn Archive"
```

Что делает:

- Читает `.txt` письма из `--source-dir`.
- Автоклассифицирует записи в: `Входящие`, `Applied`, `Reject`, `Interview`, `Manual Sort`, `Archive`.
- Хранит данные в SQLite (включая ручные изменения статусов).
- Поддерживает несколько ссылок вакансий в одном письме (1 ссылка = 1 запись).
- Подтягивает `About the job` по LinkedIn URL, когда доступно.

### 4) Нативное macOS приложение (SwiftUI)

Сборка и установка:

```bash
cd LinkInJob
./scripts/build_and_install_app.sh
```

После сборки приложение будет установлено в:

`/Applications/LinkInJob.app`

### 5) Sync из Google Drive

Если настроен `rclone`, можно запускать:

```bash
./scripts/sync_drive_rclone.sh
```

## Gmail Apps Script -> TXT архив

Используется Google Apps Script в Gmail/Drive, который сохраняет письма LinkedIn в `.txt`.
Именно эти TXT-файлы дальше обрабатываются парсером в этом проекте.

Папка архива в Drive:

`LinkedIn Archive`

Таблица трекинга:

`LinkedIn_Job_Tracker`

Текущий скрипт:

```javascript
function processLinkedInArchive() {
  const now = new Date();
  const hours = now.getHours();

  // Не работаем с 00:00 до 08:00
  if (hours >= 0 && hours < 8) {
    console.log("Ночной режим. Пропуск запуска.");
    return;
  }

  const LABEL_NAME = "LinkedIn";
  const FOLDER_NAME = "LinkedIn Archive";
  const SPREADSHEET_NAME = "LinkedIn_Job_Tracker";

  // 1. Находим папку "LinkedIn Archive"
  let folders = DriveApp.getFoldersByName(FOLDER_NAME);
  let folder = folders.hasNext() ? folders.next() : DriveApp.createFolder(FOLDER_NAME);

  // 2. Находим таблицу для трекинга
  let ss;
  let files = DriveApp.getFilesByName(SPREADSHEET_NAME);
  if (files.hasNext()) {
    ss = SpreadsheetApp.open(files.next());
  } else {
    ss = SpreadsheetApp.create(SPREADSHEET_NAME);
    ss.getSheets()[0].appendRow(["Дата", "Компания", "Статус", "Файл на Диске"]);
  }
  let sheet = ss.getSheets()[0];

  // 3. Получаем письма
  let label = GmailApp.getUserLabelByName(LABEL_NAME);
  if (!label) return;

  let threads = label.getThreads(0, 15); // Берем последние 15 веток

  threads.forEach(thread => {
    let messages = thread.getMessages();
    let lastMsg = messages[messages.length - 1];
    let subject = lastMsg.getSubject();
    let date = lastMsg.getDate();
    let formattedDate = Utilities.formatDate(date, Session.getScriptTimeZone(), "yyyy-MM-dd_HH-mm");

    let fileName = `${formattedDate} - ${subject.replace(/[/\\?%*:|"<>]/g, "")}.txt`;

    // Если файла еще нет — создаем его
    if (!folder.getFilesByName(fileName).hasNext()) {
      let content = `От: ${lastMsg.getFrom()}\nДата: ${date}\nТема: ${subject}\n\n${lastMsg.getPlainBody()}`;
      let newFile = folder.createFile(fileName, content);

      // Определяем статус
      let status = "Подано";
      let body = lastMsg.getPlainBody().toLowerCase();
      if (body.includes("viewed your application")) status = "Просмотрено";
      if (body.includes("unfortunately") || body.includes("not moving forward")) status = "Отказ";

      // Добавляем в таблицу
      sheet.appendRow([date, subject, status, newFile.getUrl()]);
      console.log("Добавлено: " + fileName);
    }
  });
}
```

## GitHub

Repository:  
[https://github.com/G5023890/LinkedIn](https://github.com/G5023890/LinkedIn)
