; ==============================
; Global Settings (AHK v2)
; ==============================
#SingleInstance Force
SendMode "Input"
SetWorkingDir A_ScriptDir

; ==============================
; WSL Snippets Root
; ==============================
WSL_DISTRO := "Ubuntu"
WSL_USER   := "nishiyama"

SNIPPET_ROOT := "\\wsl$\" WSL_DISTRO "\data\git-repos\github.com\rhi222\dotfiles\.config\AutoHotkey\ahk-snippets"

PasteFile(path) {
    if !FileExist(path) {
        MsgBox "File not found:`n" path, "Snippet Error", "Icon!"
        return
    }
    clipSaved := ClipboardAll()
    text := FileRead(path, "UTF-8")
    A_Clipboard := text
    Send "^v"
    Sleep 50
    A_Clipboard := clipSaved
}

; ==============================
; Snippet Registry（ここだけ編集すればOK）
; - key: トリガー（ホットストリング）
; - label: メニュー表示名
; - rel: SNIPPET_ROOT からの相対パス
; ==============================
SNIPPETS := Map(
    ";gm-ms", Map("label", "Prompt: Gemini-schedule",       "rel", "prompts\Gemini-my-schedule.md"),
    ";cp-vi", Map("label", "Prompt: chatGPT-voice-input",   "rel", "prompts\chatGPT-voice-input.md"),

    ";js-fa", Map("label", "JS: forcast承認",            "rel", "js\forcast-approve.js"),
    ";js-fk",    Map("label", "JS: 出社状況登録",    "rel", "js\forcast-kintai.js")
)

; ==============================
; Hotstrings auto-register (SAFE)
; ==============================
for trig, meta in SNIPPETS {
    relPath := meta["rel"]
    Hotstring(":*:" trig, (*) => PasteFile(SNIPPET_ROOT "\" relPath))
}

; ==============================
; Menu Launcher (SAFE)
; ==============================
MakePasteCallback(fullPath) {
    return (*) => PasteFile(fullPath)
}

^!s:: {
    snipMenu := Menu()
    promptMenu := Menu()
    jsMenu := Menu()

    for trig, meta in SNIPPETS {
        relPath  := meta["rel"]
        label    := meta["label"]
        fullPath := SNIPPET_ROOT "\" relPath

        cb := MakePasteCallback(fullPath)  ; ← ここで値が固定される

        if InStr(relPath, "prompts\") = 1 {
            promptMenu.Add(label " (" trig ")", cb)
        } else if InStr(relPath, "js\") = 1 {
            jsMenu.Add(label " (" trig ")", cb)
        } else {
            snipMenu.Add(label " (" trig ")", cb)
        }
    }

    snipMenu.Add("Prompts", promptMenu)
    snipMenu.Add("JavaScript", jsMenu)
    snipMenu.Show()
}

