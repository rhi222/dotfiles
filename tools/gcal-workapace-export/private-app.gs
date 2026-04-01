const SHEET_NAME = "work_events";
const CALENDAR_ID = "YOUR_CALENDAR_ID";
const SPREADSHEET_URL = "YOUR_SPREADSHEET_URL";
const USER_NAME = "YOUR_NAME";

function getTargetCalendar_() {
  const cal = CalendarApp.getCalendarById(CALENDAR_ID);
  if (!cal) throw new Error(`Calendar not found: ${CALENDAR_ID}`);
  return cal;
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu("Work Sync")
    .addItem("未登録（imported=FALSE）を個人カレンダーへ登録", "pushToPersonalCalendar")
    .addItem("上書き同期（既存イベントを更新 / 無ければ作成）", "upsertPersonalCalendar")
    .addItem("ドライラン（登録せず件数確認）", "dryRun")
    .addToUi();
}

function dryRun() {
  const rows = loadRows_();
  const targets = rows.filter(r => !r.imported && !r.gcalEventId);
  SpreadsheetApp.getUi().alert(`登録対象: ${targets.length} 件`);
}

function pushToPersonalCalendar() {
  const rows = loadRows_();
  const targets = rows.filter(r => !r.imported && !r.gcalEventId);
  const result = syncToCalendar_(targets, { allowUpdate: false });
  SpreadsheetApp.getUi().alert(`完了: ${result.created}件登録 / 失敗: ${result.failed}件`);
}

function loadRows_() {
  const sheet = SpreadsheetApp.getActive().getSheetByName(SHEET_NAME);
  if (!sheet) throw new Error(`Sheet not found: ${SHEET_NAME}`);

  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];

  const values = sheet.getRange(2, 1, lastRow - 1, 7).getValues();
  const out = [];

  values.forEach((row, i) => {
    const rowIndex = i + 2;

    const workDate = row[0];      // A
    const workType = row[1];      // B
    const office = row[2];        // C
    const memo = row[3];          // D
    const imported = row[4];      // E
    const importedAt = row[5];    // F
    const gcalEventId = row[6];   // G

    if (!workDate || !workType) return;

    out.push({
      rowIndex,
      workDate,
      workType: String(workType).trim(),
      office: String(office || "").trim(),
      memo: String(memo || "").trim(),
      imported: imported === true || String(imported).toUpperCase() === "TRUE",
      importedAt,
      gcalEventId: String(gcalEventId || "").trim(),
    });
  });

  return out;
}

function buildOptions_(t) {
  const opt = {};
  if (t.office) opt.location = t.office;

  // 説明は「memo + 元データの出所」を軽く残すと後で安心
  const desc = [];
  if (t.memo) desc.push(t.memo);
  desc.push("会社のGoogleカレンダーから自動連携");
  desc.push(`sheet: ${SPREADSHEET_URL}`);
  opt.description = desc.join("\n");
  return opt;
}

function decorateTitle_(workType) {
  if (workType === "出社") return `🏢 ${USER_NAME}出社`;
  if (workType === "在宅") return `🏠 ${USER_NAME}在宅`;
  if (workType === "有休") return `🌿 ${USER_NAME}有休`;
  return `📍 ${USER_NAME}${workType}`;
}

function ensureDate_(d) {
  if (d instanceof Date) {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    return x;
  }
  // 文字列 "YYYY-MM-DD" 等の保険
  const s = String(d).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) throw new Error(`Invalid date: ${s}`);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}


function upsertPersonalCalendar() {
  const rows = loadRows_();
  const targets = rows.filter(r => r.workDate && r.workType);
  const result = syncToCalendar_(targets, { allowUpdate: true });
  SpreadsheetApp.getUi().alert(
    `上書き同期 完了\n更新: ${result.updated}件 / 新規作成: ${result.created}件 / 失敗: ${result.failed}件`
  );
}

function syncToCalendar_(targets, opts) {
  const allowUpdate = opts.allowUpdate || false;
  const cal = getTargetCalendar_();
  const sheet = SpreadsheetApp.getActive().getSheetByName(SHEET_NAME);
  if (!sheet) throw new Error(`Sheet not found: ${SHEET_NAME}`);

  let created = 0;
  let updated = 0;
  let failed = 0;

  targets.forEach(t => {
    try {
      const date = ensureDate_(t.workDate);
      const title = decorateTitle_(t.workType);
      const eventOpts = buildOptions_(t);

      let event = null;
      if (allowUpdate && t.gcalEventId) {
        try {
          event = cal.getEventById(t.gcalEventId);
        } catch (e) {
          event = null;
        }
      }

      if (event) {
        event.setTitle(title);
        event.setAllDayDate(date);
        if (eventOpts.location !== undefined) event.setLocation(eventOpts.location);
        if (eventOpts.description !== undefined) event.setDescription(eventOpts.description);
        sheet.getRange(t.rowIndex, 5, 1, 3).setValues([[true, new Date(), t.gcalEventId]]);
        updated++;
      } else {
        const newEvent = cal.createAllDayEvent(title, date, eventOpts);
        sheet.getRange(t.rowIndex, 5, 1, 3).setValues([[true, new Date(), newEvent.getId()]]);
        created++;
      }
    } catch (e) {
      Logger.log(`Failed row ${t.rowIndex}: ${e}`);
      failed++;
    }
  });

  return { created, updated, failed };
}


