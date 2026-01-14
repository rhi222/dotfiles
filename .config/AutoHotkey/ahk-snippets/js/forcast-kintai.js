// 出社状況登録
// https://forcia.slack.com/archives/C0EE95H2B/p1630497172001400
document.querySelectorAll("#timesheet > tbody > tr.weekday").forEach(($day) => {
  console.log($day);
  const $select = $day.querySelector(".select-working-status");
  const $checkOutbound = $day.querySelector(".chk-outbound");
  const $checkInbound = $day.querySelector(".chk-inbound");
  const note = $day.querySelectorAll("td")[5].querySelector("span").innerHTML;
  if (note === "") {
    $select.value = "出社";
    $checkOutbound.checked = true;
    $checkInbound.checked = true;
  } else if (
    note.includes("午前") ||
    note.includes("午後") ||
    note.includes("日中")
  ) {
    $select.value = "出社・在宅（移動）";
    $checkOutbound.checked = true;
    $checkInbound.checked = true;
  } else {
    $select.value = "在宅勤務";
    $checkOutbound.checked = false;
    $checkInbound.checked = false;
  }
});
