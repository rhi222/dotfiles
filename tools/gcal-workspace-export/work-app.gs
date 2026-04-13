const SHEET_NAME = "work_events";

// 取りたい期間（今日から何日先まで）
const LOOKAHEAD_DAYS = 60;
// どれくらい過去も見るか（変更が起きた場合の巻き取り）
const LOOKBACK_DAYS = 14;

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu("Working Location Sync")
    .addItem("全同期（過去14日＋未来60日・新規追加あり）", "syncWorkingLocations")
    .addItem("未来のみ同期（今日以降・新規追加あり）", "syncWorkingLocationsFutureOnly")
    .addItem("既存行の更新のみ（新規行は追加しない）", "syncWorkingLocationsUpdateOnly")
    .addToUi();
}

function syncWorkingLocations() {
  const start = addDays_(startOfDay_(new Date()), -LOOKBACK_DAYS);
  const end = addDays_(startOfDay_(new Date()), LOOKAHEAD_DAYS);
  syncWorkingLocationsInRange_(start, end);
}

function syncWorkingLocationsFutureOnly() {
  const start = startOfDay_(new Date());
  const end = addDays_(startOfDay_(new Date()), LOOKAHEAD_DAYS);
  syncWorkingLocationsInRange_(start, end);
}

function syncWorkingLocationsUpdateOnly() {
  const start = addDays_(startOfDay_(new Date()), -LOOKBACK_DAYS);
  const end = addDays_(startOfDay_(new Date()), LOOKAHEAD_DAYS);
  syncWorkingLocationsInRangeUpdateOnly_(start, end);
}

function syncWorkingLocationsInRange_(timeMin, timeMax) {
  syncCore_(timeMin, timeMax, { updateOnly: false });
}

function syncWorkingLocationsInRangeUpdateOnly_(timeMin, timeMax) {
  syncCore_(timeMin, timeMax, { updateOnly: true });
}

function syncCore_(timeMin, timeMax, opts) {
  const updateOnly = opts.updateOnly || false;
  const sheet = getOrCreateSheet_();
  ensureHeader_(sheet);

  const existing = indexExistingByDate_(sheet);

  const items = listEvents_(timeMin, timeMax)
    .filter(e => e.eventType === "workingLocation");

  if (items.length === 0) {
    SpreadsheetApp.getUi().alert("対象の workingLocation イベントが見つかりませんでした");
    return;
  }

  // 1日ごとに「updated が最新」の workingLocation を採用する
  const bestByDate = new Map();
  items.forEach(ev => {
    const rows = explodeWorkingLocationEvent_(ev);
    const updated = String(ev.updated || "");
    rows.forEach(r => {
      const key = r.work_date;
      const current = bestByDate.get(key);
      if (!current || updated > current.updated) {
        bestByDate.set(key, { row: r, updated });
      }
    });
  });

  let upserts = 0;
  let updates = 0;

  if (updateOnly) {
    bestByDate.forEach(v => {
      const rowIndex = existing.get(v.row.work_date);
      if (rowIndex) {
        sheet.getRange(rowIndex, 2, 1, 3).setValues([[v.row.work_type, v.row.office, v.row.memo]]);
        updates++;
      }
    });
  } else {
    bestByDate.forEach(v => {
      upsertRow_(sheet, existing, v.row);
      upserts++;
    });
  }

  sortByWorkDate_(sheet);

  const msg = updateOnly
    ? `更新完了: ${updates} 件を更新しました（新規行は追加していません）`
    : `同期完了: ${upserts} 件（workingLocation）を反映しました`;
  SpreadsheetApp.getUi().alert(msg);
}

function listEvents_(timeMin, timeMax) {
  const calendarId = "primary";
  const results = [];

  let pageToken = null;
  try {
    do {
      const resp = Calendar.Events.list(calendarId, {
        timeMin: timeMin.toISOString(),
        timeMax: timeMax.toISOString(),
        singleEvents: true,
        orderBy: "startTime",
        maxResults: 2500,
        pageToken,
      });
      if (resp.items && resp.items.length) results.push(...resp.items);
      pageToken = resp.nextPageToken;
    } while (pageToken);
  } catch (e) {
    Logger.log(`Calendar API error: ${e}`);
    return [];
  }

  return results;
}

/**
 * workingLocation event -> [{work_date, work_type, office, memo}]
 */
function explodeWorkingLocationEvent_(ev) {
  // working location は多くの場合 all-day で start.date / end.date（endは排他的）
  const startDateStr = ev.start?.date;
  const endDateStr = ev.end?.date;

  // フォールバック（万一 dateTime 形式で来た場合）
  const start = startDateStr ? parseYmd_(startDateStr) : new Date(ev.start?.dateTime);
  const endExclusive = endDateStr ? parseYmd_(endDateStr) : new Date(ev.end?.dateTime);

  const props = ev.workingLocationProperties || {};
  const type = props.type; // homeOffice / officeLocation / customLocation

  // ラベル系（存在すれば拾う）
  const officeLabel = props.officeLocation?.label || "";
  const customLabel = props.customLocation?.label || "";

  const mapped = mapWorkType_(type, officeLabel, customLabel);

  // endExclusive の前日まで展開
  const rows = [];
  for (let d = startOfDay_(start); d < endExclusive; d = addDays_(d, 1)) {
    rows.push({
      work_date: formatYmd_(d),
      work_type: mapped.work_type,
      office: mapped.office,
      memo: mapped.memo,
    });
  }
  return rows;
}

function mapWorkType_(type, officeLabel, customLabel) {
  if (type === "homeOffice") {
    return { work_type: "在宅", office: "", memo: "" };
  }
  if (type === "officeLocation") {
    return { work_type: "出社", office: officeLabel || "オフィス", memo: "" };
  }
  if (type === "customLocation") {
    if (/有休|有給|休暇/.test(customLabel)) {
      return { work_type: "有休", office: "", memo: customLabel };
    }
    return { work_type: "外出", office: customLabel || "", memo: "" };
  }
  // 不明タイプ
  return { work_type: "外出", office: customLabel || officeLabel || "", memo: "" };
}

function upsertRow_(sheet, existingIndex, r) {
  const rowIndex = existingIndex.get(r.work_date);

  if (rowIndex) {
    // update
    sheet.getRange(rowIndex, 2, 1, 3).setValues([[r.work_type, r.office, r.memo]]);
  } else {
    // append
    const newRow = sheet.getLastRow() + 1;
    sheet.getRange(newRow, 1, 1, 4).setValues([[r.work_date, r.work_type, r.office, r.memo]]);
    existingIndex.set(r.work_date, newRow);
  }
}

function indexExistingByDate_(sheet) {
  const lastRow = sheet.getLastRow();
  const map = new Map();
  if (lastRow < 2) return map;

  const values = sheet.getRange(2, 1, lastRow - 1, 1).getValues(); // A列
  values.forEach((v, i) => {
    const cell = v[0];
    if (!cell) return;
    // Spreadsheetが日付をDateオブジェクトとして返す場合があるため正規化
    const dateStr = cell instanceof Date ? formatYmd_(cell) : String(cell).trim();
    if (dateStr) map.set(dateStr, i + 2);
  });
  return map;
}

function getOrCreateSheet_() {
  const ss = SpreadsheetApp.getActive();
  return ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);
}

function ensureHeader_(sheet) {
  const header = sheet.getRange(1, 1, 1, 4).getValues()[0];
  const want = ["work_date", "work_type", "office", "memo"];
  const ok = want.every((w, i) => header[i] === w);
  if (!ok) sheet.getRange(1, 1, 1, 4).setValues([want]);
}

function startOfDay_(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}
function addDays_(d, days) {
  const x = new Date(d);
  x.setDate(x.getDate() + days);
  return x;
}
function parseYmd_(s) {
  // "YYYY-MM-DD"
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}
function formatYmd_(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}


function sortByWorkDate_(sheet) {
  const lastRow = sheet.getLastRow();
  const lastCol = sheet.getLastColumn();
  if (lastRow <= 2) return; // データがほぼ無い

  // ヘッダー除外して、A列（work_date）で昇順ソート
  sheet.getRange(2, 1, lastRow - 1, lastCol).sort({ column: 1, ascending: true });
}

function debugWorkingLocationOn_(ymd) {
  const day = parseYmd_(ymd);
  const timeMin = startOfDay_(day);
  const timeMax = addDays_(startOfDay_(day), 1);

  const items = listEvents_(timeMin, timeMax)
    .filter(e => e.eventType === "workingLocation");

  Logger.log(`--- workingLocation events on ${ymd}: ${items.length} ---`);
  items.forEach(e => {
    const p = e.workingLocationProperties || {};
    Logger.log(JSON.stringify({
      id: e.id,
      updated: e.updated,
      start: e.start,
      end: e.end,
      type: p.type,
      officeLabel: p.officeLocation?.label || "",
      customLabel: p.customLocation?.label || "",
      summary: e.summary || "",
    }));
  });
}




