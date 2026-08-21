package wsl

import "os/exec"

// lookPath は PATH からコマンドを探す。テストから差し替えられるよう変数にしている。
var lookPath = exec.LookPath
