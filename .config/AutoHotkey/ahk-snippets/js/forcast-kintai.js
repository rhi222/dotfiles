// forcast 出社状況登録
// https://forcia.slack.com/archives/C0EE95H2B/p1630497172001400
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function findDocHaving(selector, { tries = 50, interval = 200 } = {}) {
  for (let t = 0; t < tries; t++) {
    // top document
    if (document.querySelector(selector)) return document;

    // same-origin iframes
    for (const f of document.querySelectorAll("iframe")) {
      try {
        const d = f.contentDocument;
        if (d?.querySelector(selector)) return d;
      } catch (_) {
        // cross-origin: cannot access
      }
    }

    await sleep(interval);
  }
  return null;
}

function fire(el) {
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
}

function setSelectValue(selectEl, value) {
  selectEl.value = value;
  fire(selectEl);
}

function setChecked(cb, checked) {
  cb.checked = checked;
  fire(cb);
}

function apply(doc) {
  doc.querySelectorAll("#timesheet > tbody > tr.weekday").forEach(($day) => {
    const $select = $day.querySelector(".select-working-status");
    const $out = $day.querySelector(".chk-outbound");
    const $in = $day.querySelector(".chk-inbound");
    if (!$select || !$out || !$in) return;

    const tds = $day.querySelectorAll("td");
    const note = (tds[5]?.querySelector?.("span")?.textContent ?? "").trim();

    if (!note) {
      setSelectValue($select, "出社");
      setChecked($out, true);
      setChecked($in, true);
    } else if (
      note.includes("午前") ||
      note.includes("午後") ||
      note.includes("日中")
    ) {
      setSelectValue($select, "出社・在宅（移動）");
      setChecked($out, true);
      setChecked($in, true);
    } else {
      setSelectValue($select, "在宅勤務");
      setChecked($out, false);
      setChecked($in, false);
    }
  });
}

(async () => {
  const doc = await findDocHaving("#timesheet");
  if (!doc) {
    console.warn(
      "Could not find #timesheet in accessible documents (maybe cross-origin iframe). Switch console context to the iframe and retry.",
    );
    return;
  }
  apply(doc);
  console.log("applied on doc:", doc === document ? "top" : "iframe");
})();
