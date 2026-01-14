// 未承認申請の一番上
document
  .querySelector(
    ".runtime_approval_processPendingApprovalCard .pendingApprovalCardList > li button",
  )
  .click();

// プルダウンで「承認」
document
  .querySelector(
    "#brandBand_2 > div > div > div > div > div > div > div.colMain > div.top > div:nth-child(1) > div > article > div.slds-card__body.slds-card__body--inner > ul > li:nth-child(1) > div.slds-grid.slds-grid--align-spread.slds-has-flexi-truncate > div > div.uiMenuList.uiMenuList--right.popupTargetContainer.uiPopupTarget.uiMenuList--default.uiPopupTarget.uiMenuList.uiMenuList--default > div > ul > li:nth-child(1) > a",
  )
  .click();

await new Promise((resolve) => setTimeout(resolve, 1000)); // 1秒待つ

// モーダルで「承認」
document
  .querySelector(
    "body > div.desktop.container.forceStyle.oneOne.navexDesktopLayoutContainer.lafAppLayoutHost.forceAccess > div.DESKTOP.uiContainerManager > div > div.panel.slds-modal.slds-fade-in-open > div > div.modal-footer.slds-modal__footer > div > button.slds-button.slds-button_neutral.modal-button-left.actionButton.uiButton--default.uiButton--brand.uiButton",
  )
  .click();
