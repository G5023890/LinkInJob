# LinkedIn Applications Tracker

This project contains:

- A script to parse exported LinkedIn/job emails and update your Obsidian note automatically (`scripts/update_linkedin_applications.py`)
- A SQL-backed desktop shell to visualize folder hierarchy (`scripts/folder_shell_sql.py`)
- A graphical SQL app for LinkedIn applications with auto status + manual control (`scripts/linkedin_applications_gui_sql.py`)

## Project Structure

- `/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/update_linkedin_applications.py`  
  Parses `.txt` emails and updates categorized company lists in markdown.
- `/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/setup_rclone_drive.sh`  
  Helper to configure rclone Google Drive remote.
- `/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/sync_drive_rclone.sh`  
  Helper to sync email files from Google Drive folder.
- `/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/folder_shell_sql.py`  
  Runs an interactive SQL-backed program in terminal: scans a data source directory, stores hierarchy in SQLite, and lets you browse it as a tree shell.
- `/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/linkedin_applications_gui_sql.py`  
  Desktop GUI for applications. Auto classifies by status (`applied/interview/rejected/review`) and lets you manually move cards between statuses, with SQL persistence.

## Requirements

- Python 3
- (Optional) `rclone` for Drive sync scripts
- `PySide6` for graphical interface:

```bash
python3 -m pip install PySide6
```

## Usage

### 1) Update Obsidian markdown from email files

Default command:

```bash
python3 /Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/update_linkedin_applications.py
```

By default, it reads emails from:

`/Users/grigorymordokhovich/Desktop/CV/LinkedIn email`

and writes to:

`/Users/grigorymordokhovich/Library/Mobile Documents/iCloud~md~obsidian/Documents/M.Greg/Работа/Поданные и откланенные заявки/System_Administrator.md`

You can override paths:

```bash
python3 /Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/update_linkedin_applications.py \
  --source-dir "/path/to/email-txt-files" \
  --target-file "/path/to/output.md"
```

### 2) SQL shell for folder hierarchy (program)

Start interactive program (default source is current directory):

```bash
python3 /Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/folder_shell_sql.py
```

Custom source and DB path:

```bash
python3 /Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/folder_shell_sql.py \
  "/path/to/source-folder" \
  --db "/path/to/hierarchy.db" \
  --sync-first
```

Inside the program:

- Set only the data source path.
- Use `sync` command to refresh data in SQLite.
- Browse tree by indexes (`1`, `2`, ...), go back with `..`, and print subtree with `tree 3`.
- Rendering reads data from SQL (not directly from filesystem).

### 3) Graphical SQL interface for applications

Run GUI:

```bash
python3 /Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/linkedin_applications_gui_sql.py \
  --source-dir "/Users/grigorymordokhovich/Desktop/CV/LinkedIn email"
```

What it does:

- Reads `.txt` LinkedIn emails from `--source-dir`.
- Auto classifies each record into `Входящие`, `Applied`, `Reject`, `Interview`, or `Manual Sort`.
- Stores everything in SQLite (manual moves are persisted).
- Lets you manually reassign status from GUI buttons.
- Fetches and shows `About the job` from LinkedIn by job URL found in email.
- Keeps URL hidden in UI and opens it only via `Open Job Link` button.
- If one email has multiple job links, it is split into multiple records (one link = one record).
- Existing links are deduplicated in SQL (already known links are ignored on sync).
- Company, role, and About the job are parsed from the job link when available.

### 4) Gmail Apps Script -> TXT archive (source for parser)

We use a Google Apps Script in Gmail/Drive that exports LinkedIn emails into plain `.txt` files.
These files are then consumed by parser/sync pipeline in this project.

Default archive folder created by script:

`LinkedIn Archive`

Tracking spreadsheet created by script:

`LinkedIn_Job_Tracker`

Script currently used:

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
    
    let fileName = `${formattedDate} - ${subject.replace(/[/\\?%*:|"<>]/g, '')}.txt`;

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

## Output Sections

The script updates markdown with this hierarchy:

- `#Компании с поданным резюме`
- `#Компании ответившие отказом`
- `#Компании пригласившие на интервью`

## GitHub

Repository:

[https://github.com/G5023890/LinkedIn](https://github.com/G5023890/LinkedIn)
