(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  async function waitFor(fn, { timeout = 15000, interval = 100 } = {}) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const v = fn();
      if (v) return v;
      await sleep(interval);
    }
    throw new Error("waitFor timeout");
  }

  function byText(root, selector, text) {
    const els = [...root.querySelectorAll(selector)];
    return els.find((el) => (el.textContent || "").trim() === text) || null;
  }

  function click(el) {
    // クリックできない要素/不可視を避けたいならここで判定を強化できる
    el.scrollIntoView?.({ block: "center", inline: "center" });
    el.click();
  }

  // ① 未承認申請の一番上をクリック
  const firstPendingBtn = await waitFor(() =>
    document.querySelector(
      ".runtime_approval_processPendingApprovalCard .pendingApprovalCardList > li button",
    ),
  );
  click(firstPendingBtn);

  // ② 「承認」メニューが出るまで待って「承認」をクリック
  //    ここは “ul > li:nth-child(1) > a” みたいなパスは捨てて、
  //    メニュー内のリンクテキストで取るのが安定しやすい
  const approveMenuItem = await waitFor(() => {
    // 開いたメニューはだいたい role="menu" / slds dropdown になってることが多い
    // まず「表示されている」メニュー候補からテキスト一致を探す
    const menus = [
      ...document.querySelectorAll(
        'div[role="menu"], ul[role="menu"], .uiMenuList',
      ),
    ];
    for (const m of menus) {
      const a = byText(m, "a, button", "承認");
      if (a) return a;
    }
    return null;
  });
  click(approveMenuItem);

  // ③ モーダルが出るまで待って、フッターの「承認」ボタンをクリック
  const modalApproveBtn = await waitFor(() => {
    // Salesforceのモーダルは role="dialog" が付くことが多い
    const modal =
      document.querySelector(
        '.slds-modal.slds-fade-in-open, [role="dialog"]',
      ) || document.querySelector(".slds-modal");
    if (!modal) return null;

    // フッター内のボタンで「承認」を探す
    return (
      byText(modal, "button", "承認") ||
      byText(document, ".slds-modal button", "承認") ||
      null
    );
  });

  click(modalApproveBtn);

  console.log("Done");
})();
[];
