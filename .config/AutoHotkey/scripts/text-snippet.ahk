; host path
; C:\Users\{user name}\Documents\AutoHotkey
; ============================================================
; AutoHotkey v2 - Snippet Paster (WSL share)
; ============================================================
; NOTE:
; - #SingleInstance / SendMode / SetWorkingDir は書かない
; - include される前提のモジュール

; ----------------------------
; Config
; ----------------------------
WSL_DISTRO := "Ubuntu"
WSL_USER   := "nishiyama"

; WSL share root (\\wsl$\Ubuntu\...)
; NOTE: If WSL isn't running, this path may temporarily fail.
SNIPPET_ROOT := "\\wsl$\" WSL_DISTRO "\data\git-repos\github.com\rhi222\dotfiles\.config\AutoHotkey\ahk-snippets"

; How long to wait for clipboard to become ready (sec)
CLIPWAIT_SEC := 1.5

; ----------------------------
; Snippet Registry (edit here)
; key: hotstring trigger
; label: menu label
; rel: path relative to SNIPPET_ROOT
; group: menu group (optional). If omitted, derived from rel prefix.
; ----------------------------
SNIPPETS := Map(
    ";gm-ms", Map("label", "Prompt: Gemini-schedule",       "rel", "prompts\Gemini-my-schedule.md"),
    ";cp-vi", Map("label", "Prompt: chatGPT-voice-input",   "rel", "prompts\chatGPT-voice-input.md"),

    ";js-fa", Map("label", "JS: forcast承認",              "rel", "js\forcast-approve.js"),
    ";js-fk", Map("label", "JS: 出社状況登録",              "rel", "js\forcast-kintai.js"),

    ";md-sd", Map("label", "Markdown: summary-detail tag",              "rel", "markdown\summary-detail.md")
)

; ============================================================
; Utilities
; ============================================================

JoinPath(base, rel) {
    ; Normalize: remove trailing "\" on base; remove leading "\" on rel
    base := RTrim(base, "\/")
    rel  := LTrim(rel, "\/")
    return base "\" rel
}

InferGroup(rel) {
    ; Expand as you like
    if InStr(rel, "prompts\") = 1
        return "Prompts"
    if InStr(rel, "js\") = 1
        return "JavaScript"
    if InStr(rel, "markdown\") = 1
        return "Markdown"
    return "Other"
}

EnsureWSLRunning(distro) {
    ; If WSL isn't running, \\wsl$ access can fail.
    ; This "ping" usually wakes it up quickly.
    ; We don't hard-fail if this fails; we just try.
    try {
        RunWait(A_ComSpec ' /c wsl.exe -d "' distro '" -e sh -lc "true"', , "Hide")
    }
}

ReadTextFileUtf8(path) {
    ; Read file robustly (UTF-8 / UTF-8 BOM)
    ; If your files may be UTF-16 etc., adjust here.
    try {
        text := FileRead(path, "UTF-8")
    } catch as e {
        ; fallback: try without encoding hint
        try text := FileRead(path)
        catch as e2 {
            throw e2
        }
    }

    ; Strip UTF-8 BOM if present (U+FEFF)
    if (SubStr(text, 1, 1) = Chr(0xFEFF))
        text := SubStr(text, 2)

    return text
}

PasteText(text) {
    ; Clipboard-safe paste:
    ; - Always restore previous clipboard (even on error)
    ; - Wait for clipboard to accept new content
    ; - Avoid too-short sleeps that may restore too early
    clipSaved := ClipboardAll()
    try {
        A_Clipboard := ""          ; clear first to make ClipWait reliable
        A_Clipboard := text
        if !ClipWait(CLIPWAIT_SEC) {
            throw Error("Clipboard did not update in time.")
        }
        Send "^v"
        ; Small delay so target app consumes paste before restoring clipboard
        Sleep 120
    } finally {
        A_Clipboard := clipSaved
    }
}

PasteFile(path, *) {
    ; Try waking WSL first (cheap + helps reliability)
    EnsureWSLRunning(WSL_DISTRO)

    if !FileExist(path) {
        MsgBox(
            "File not found:`n" path "`n`n"
            "ヒント:`n"
            "- WSLが起動していないと \\wsl$ が見えないことがあります`n"
            "- SNIPPET_ROOT / rel のパスを確認してください",
            "Snippet Error",
            "Icon!"
        )
        return
    }

    try {
        text := ReadTextFileUtf8(path)
        PasteText(text)
    } catch as e {
        MsgBox(
            "Failed to paste snippet.`n`n"
            "Path:`n" path "`n`n"
            "Error:`n" e.Message,
            "Snippet Error",
            "Icon!"
        )
    }
}

; ============================================================
; Hotstrings
; ============================================================
for trig, meta in SNIPPETS {
    fullPath := JoinPath(SNIPPET_ROOT, meta["rel"])
    ; :*: = trigger immediately when typed (no ending char needed)
    ; If you prefer safer boundary behavior, consider :*?:
    Hotstring(":*:" trig, PasteFile.Bind(fullPath))
}

; ============================================================
; Menu Hotkey
; ============================================================
^!s:: {
    EnsureWSLRunning(WSL_DISTRO)

    rootMenu := Menu()
    groups := Map() ; groupName -> Menu

    ; Build group menus dynamically
    for trig, meta in SNIPPETS {
        rel      := meta["rel"]
        label    := meta["label"]
        fullPath := JoinPath(SNIPPET_ROOT, rel)
        cb       := PasteFile.Bind(fullPath)

        group := meta.Has("group") ? meta["group"] : InferGroup(rel)

        if !groups.Has(group)
            groups[group] := Menu()

        groups[group].Add(label " (" trig ")", cb)
    }

    ; Add groups in a stable order (optional)
    preferred := ["Prompts", "JavaScript", "Other"]
    for _, g in preferred {
        if groups.Has(g)
            rootMenu.Add(g, groups[g])
    }
    ; Add any remaining groups
    for g, m in groups {
        if (preferred.Has(g))
            continue
        rootMenu.Add(g, m)
    }

    rootMenu.Show()
}
