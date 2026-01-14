#Requires AutoHotkey v2.0
;; 矢印キーをvimlikeに
^h::Left
^j::Down
^k::Up
^l::Right

MsgBox "setting done!"

; v1
;; ref urls
;; https://freesoft-concierge.com/utility/autohotkey/
;; https://qiita.com/chr/items/47f50e36703d3bb20371
;; https://wg16.hatenablog.jp/entry/autohotkey_001
;; Symbols: https://www.autohotkey.com/docs/Hotkeys.htm#Symbols
;
;;; vim mapping
;;; https://www.autohotkey.com/docs/commands/GetKeyState.htm
;;; http://blog.livedoor.jp/sourceof/archives/6147520.html
;;; http://wafu.hatenadiary.com/entry/2017/05/27/185627
;^h::Send,{Left}
;^j::Send,{Down}
;^k::Send,{Up}
;^l::Send,{Right}
;
;;; 範囲選択
;+^h::Send,+{Left}
;+^j::Send,+{Down}
;+^k::Send,+{Up}
;+^l::Send,+{Right}
;
;;; work around for win arrow
;;; https://autohotkey.com/board/topic/118717-noob-windows-shift-leftright-arrow-by-pressing-one-key-f12/
;#+^h:: Send #+{Left}
;#+^l:: Send #+{Right}
;
;#^h:: Send #{Left}
;#^l:: Send #{Right}
;#^j:: Send #{Down}
;#^k:: Send #{Up}
;
;;; capslock -> Ctrl
;;; https://www.autohotkey.com/boards/viewtopic.php?t=81750
;;; CapsLock::Control
;
; msgbox setting done!
