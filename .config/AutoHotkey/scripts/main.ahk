#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Input"
SetWorkingDir A_ScriptDir

; PC依存差分があれば読み込み（任意）
#Include *i local.ahk

#Include "keymap-vimlike.ahk"
#Include "text-snippet.ahk"

; Ctrl + Alt + Rでreload
; neovimなどwsl側の設定とぶつかるようなら消す
^!r::Reload
