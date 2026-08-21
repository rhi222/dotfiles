package command

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

// confirmTTY は /dev/tty から y/N を読む。
//
// **stdin から読まない。** 掃除コマンドは他のコマンドからパイプで呼ばれることが
// あり、stdin が塞がっていると承認を取り損なう。y / yes（大小問わず）だけを
// 承認として扱う。
func confirmTTY(prompt string, w io.Writer) bool {
	tty, err := os.Open("/dev/tty")
	if err != nil {
		return false
	}
	defer func() { _ = tty.Close() }()

	if w != nil {
		fmt.Fprint(w, prompt)
	}
	sc := bufio.NewScanner(tty)
	if !sc.Scan() {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(sc.Text())) {
	case "y", "yes":
		return true
	default:
		return false
	}
}
