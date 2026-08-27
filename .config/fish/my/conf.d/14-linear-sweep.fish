# Linearスイープの取りこぼし補完
#
# スイープ本体は cron（平日8:00）で回しているが、WSL2のcronは**PCが停止していた時刻の
# ジョブを実行しない**。anacron も入れていないため、8:00に起動していない日はその日の
# スイープが丸ごと落ちる。
#
# そこで、その日の最初のインタラクティブシェル起動時にも1回だけ走らせる。
# スクリプト側の `--if-not-today` が当日実行済みかを見るので、シェルを何枚開いても
# 1日1回に収まる。cronが先に走った日はここでは何もしない（逆も同じ）。
#
# 起動を待たせないため background + disown に逃がす。結果は次に Linear を
# 開いたときに見えていればよく、シェル起動時に表示する必要はない。
# 出力を捨てているのは、gh/API のエラーでプロンプトを汚さないため。ログが要る場合は
# ~/.linear-sweep.log を見る cron 側の実行を参照する。

if status is-interactive
    if test -x "$HOME/scripts/linear/sweep.sh"
        "$HOME/scripts/linear/sweep.sh" --if-not-today >/dev/null 2>&1 &
        disown
    end
end
