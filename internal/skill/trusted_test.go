// trusted owner判定は完全一致かつdefault-denyで、宣言欠落時に未検証skillを許可しない。
package skill

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeAllowlist(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "trusted-skill-owners.txt")
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestIsTrustedOwnerParsesDeclaration(t *testing.T) {
	p := writeAllowlist(t, "# コメント行は無視する\nanthropics\n\n  github  \nvercel-labs # 行末コメント\n")

	for _, owner := range []string{"anthropics", "github", "vercel-labs"} {
		if !IsTrustedOwner(p, owner) {
			t.Errorf("%q を信頼済みと判定しない", owner)
		}
	}
	for _, owner := range []string{"someone", "", "#", "コメント行は無視する"} {
		if IsTrustedOwner(p, owner) {
			t.Errorf("%q を信頼済みと判定してしまう", owner)
		}
	}
}

func TestIsTrustedOwnerIsExactMatch(t *testing.T) {
	// **部分一致で通してはいけない。** anthropics-evil のような名前が
	// anthropics として通ると allowlist の意味が無くなる
	p := writeAllowlist(t, "anthropics\n")
	for _, owner := range []string{"anthropic", "anthropicss", "anthropics-evil", "xanthropics"} {
		if IsTrustedOwner(p, owner) {
			t.Errorf("%q を通してしまう", owner)
		}
	}
}

func TestIsTrustedOwnerFailsClosedWhenFileMissing(t *testing.T) {
	// **ファイルが無ければ拒否する（fail-closed）。** secret-scan の辞書とは
	// 逆に倒している。辞書不在で commit できないのは困るが、allowlist 不在で
	// skill が入らないのは機能が欠けるだけで害がない
	if IsTrustedOwner(filepath.Join(t.TempDir(), "nope.txt"), "anthropics") {
		t.Error("ファイルが無いのに通してしまう")
	}
	if IsTrustedOwner("", "anthropics") {
		t.Error("パスが空なのに通してしまう")
	}
}

func TestIsTrustedOwnerFailsClosedWhenEmpty(t *testing.T) {
	p := writeAllowlist(t, "# コメントだけ\n\n")
	if IsTrustedOwner(p, "anthropics") {
		t.Error("空の allowlist で通してしまう")
	}
}

func TestRequireTrustedOwnerGuidesToVendoring(t *testing.T) {
	p := writeAllowlist(t, "anthropics\n")

	var w bytes.Buffer
	if RequireTrustedOwner(p, "anthropics/skills", &w) != true {
		t.Error("信頼済み owner を拒否した")
	}
	if w.String() != "" {
		t.Errorf("通したのに何か出力した: %q", w.String())
	}

	w.Reset()
	if RequireTrustedOwner(p, "someone/private", &w) != false {
		t.Error("allowlist 外を通した")
	}
	// **拒否したら次の手を案内する。** ここで止まったままだと利用者が
	// allowlist に自分で足してしまう（それは「レビューなしで自動更新」を許すこと）
	if !strings.Contains(w.String(), "skills/vendor.sh add someone/private") {
		t.Errorf("vendoring への導線が無い: %q", w.String())
	}
	if !strings.Contains(w.String(), "someone") {
		t.Errorf("どの owner が拒否されたか出ていない: %q", w.String())
	}
}

func TestRequireTrustedOwnerHandlesRepoWithoutSlash(t *testing.T) {
	p := writeAllowlist(t, "anthropics\n")
	var w bytes.Buffer
	// owner/repo でない入力は owner 全体として扱う（allowlist に無ければ拒否）
	if RequireTrustedOwner(p, "anthropics", &w) != true {
		t.Errorf("owner だけの入力を拒否した: %q", w.String())
	}
}
