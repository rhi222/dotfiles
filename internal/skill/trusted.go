package skill

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

// IsTrustedOwner は owner が allowlist にあるか。
//
// **ファイルが無ければ拒否する（fail-closed）。** secret-scan の辞書とは逆に
// 倒している。辞書不在で commit できないのは困るが、allowlist 不在で skill が
// 入らないのは機能が欠けるだけで害がない。
//
// allowlist に入れることは「人のレビューなしで毎日自動更新される」ことと同義
// なので、既定は default-deny。
func IsTrustedOwner(allowlistPath, owner string) bool {
	f, err := os.Open(allowlistPath)
	if err != nil {
		return false
	}
	defer func() { _ = f.Close() }()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if line == owner {
			return true
		}
	}
	return false
}

// RequireTrustedOwner は repo（owner/name 形式）の owner が信頼済みか調べる。
// 信頼できないときは vendoring への導線を stderr へ出して false を返す。
func RequireTrustedOwner(allowlistPath, repo string, w io.Writer) bool {
	owner := repo
	if i := strings.Index(repo, "/"); i >= 0 {
		owner = repo[:i]
	}
	if IsTrustedOwner(allowlistPath, owner) {
		return true
	}
	fmt.Fprintf(w, `Error: owner '%s' は trusted-skill-owners.txt に無い
  gh skill の自動同期は信頼済み owner に限定している（毎日レビューなしで更新されるため）。
  vendoring して取り込む:
    bash scripts/skills/vendor.sh add %s <sub-path> [name]
`, owner, repo)
	return false
}
