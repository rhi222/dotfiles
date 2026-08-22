// settings同期は実体を正として方向を守り、競合や壊れた入力をforceなしに上書きしない。
// 書込みはatomicに行い、既存権限とlive側のsecretを保持する。
package settings

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// 同期フローの検査。**pull / push / status の安全弁がここの主題。**
//   - 壊れた設定を相手側へ伝播させない
//   - push は差分があれば --force なしで書かない
//   - 実ファイルの権限（600）を崩さない

func newIO() (IO, *bytes.Buffer, *bytes.Buffer) {
	var out, errOut bytes.Buffer
	return IO{Stdout: &out, Stderr: &errOut}, &out, &errOut
}

// realDiff は diff を実際に呼ぶ Runner。表示の体裁を実物で確かめるため。
func realDiff() execx.Runner { return execx.New() }

func writeJSON(t *testing.T, path, body string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func claudeSetup(t *testing.T) (ClaudeConfig, string) {
	t.Helper()
	dir := t.TempDir()
	return ClaudeConfig{
		Live:       filepath.Join(dir, "live", "settings.json"),
		Repo:       filepath.Join(dir, "repo", "settings.json"),
		SecretDict: filepath.Join(dir, "secret-patterns.txt"),
	}, dir
}

func TestClaudePullTakesLiveIntoRepo(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Live, `{"b":1,"a":2}`, 0o600)

	w, out, _ := newIO()
	if got := ClaudePull(context.Background(), realDiff(), cfg, false, w); got != Written {
		t.Fatalf("Outcome = %v, want Written（%s）", got, out.String())
	}
	body, err := os.ReadFile(cfg.Repo)
	if err != nil {
		t.Fatal(err)
	}
	// 正規化されて入る（キー順が安定する）
	if want := "{\n  \"a\": 2,\n  \"b\": 1\n}\n"; string(body) != want {
		t.Errorf("got %q, want %q", body, want)
	}
}

func TestClaudePullIsNoopWhenSame(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Live, `{"a":1}`, 0o600)
	writeJSON(t, cfg.Repo, "{\n  \"a\": 1\n}\n", 0o644)

	w, out, _ := newIO()
	if got := ClaudePull(context.Background(), realDiff(), cfg, false, w); got != Unchanged {
		t.Fatalf("Outcome = %v, want Unchanged", got)
	}
	if !strings.Contains(out.String(), "変更なし") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestClaudePullDryRunShowsDiffWithoutWriting(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Live, `{"a":2}`, 0o600)
	writeJSON(t, cfg.Repo, "{\n  \"a\": 1\n}\n", 0o644)

	w, out, _ := newIO()
	if got := ClaudePull(context.Background(), realDiff(), cfg, true, w); got != WouldWrite {
		t.Fatalf("Outcome = %v, want WouldWrite", got)
	}
	if !strings.Contains(out.String(), "--dry-run") {
		t.Errorf("dry-run と言っていない: %q", out.String())
	}
	// **差分を見せる**（何が変わるか分からないと判断できない）
	if !strings.Contains(out.String(), `"a": 2`) {
		t.Errorf("差分を出していない: %q", out.String())
	}
	body, _ := os.ReadFile(cfg.Repo)
	if string(body) != "{\n  \"a\": 1\n}\n" {
		t.Errorf("dry-run なのに書き込んだ: %q", body)
	}
}

func TestClaudePullRejectsBrokenLive(t *testing.T) {
	// **壊れた設定をリポジトリへ伝播させない門番。**
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Live, `{"a":`, 0o600)

	w, _, errOut := newIO()
	if got := ClaudePull(context.Background(), realDiff(), cfg, false, w); got != Failed {
		t.Fatalf("Outcome = %v, want Failed", got)
	}
	if !strings.Contains(errOut.String(), "正しいJSONではありません") {
		t.Errorf("stderr = %q", errOut.String())
	}
	if _, err := os.Stat(cfg.Repo); err == nil {
		t.Error("壊れた内容を書き込んだ")
	}
}

func TestClaudePullMasksSecrets(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.SecretDict, "example-corp\n", 0o600)
	writeJSON(t, cfg.Live, `{"enabledPlugins":{"p@example-corp":true,"q@anthropics":true}}`, 0o600)

	w, _, _ := newIO()
	if got := ClaudePull(context.Background(), realDiff(), cfg, false, w); got != Written {
		t.Fatalf("Outcome = %v", got)
	}
	body, _ := os.ReadFile(cfg.Repo)
	if strings.Contains(string(body), "example-corp") {
		t.Errorf("機密がリポジトリへ入った:\n%s", body)
	}
	if !strings.Contains(string(body), "q@anthropics") {
		t.Errorf("公開分が落ちている:\n%s", body)
	}
}

func TestClaudePushCreatesWhenLiveMissing(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Repo, `{"a":1}`, 0o644)

	w, out, _ := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, false, w); got != Created {
		t.Fatalf("Outcome = %v, want Created（%s）", got, out.String())
	}
	if _, err := os.Stat(cfg.Live); err != nil {
		t.Errorf("実ファイルを作っていない: %v", err)
	}
}

func TestClaudePushRefusesWhenDifferentWithoutForce(t *testing.T) {
	// **これが安全弁。** /config での操作を黙って捨てないための門
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Repo, `{"theme":"dark"}`, 0o644)
	writeJSON(t, cfg.Live, `{"theme":"light"}`, 0o600)

	w, _, errOut := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, false, w); got != Rejected {
		t.Fatalf("Outcome = %v, want Rejected", got)
	}
	if got := Rejected.ExitCode(); got != 1 {
		t.Errorf("ExitCode = %d, want 1", got)
	}
	if !strings.Contains(errOut.String(), "push しません") {
		t.Errorf("理由を出していない: %q", errOut.String())
	}
	// **pull を案内する**（どうすればよいか分かるように）
	if !strings.Contains(errOut.String(), "pull") {
		t.Errorf("次の手を案内していない: %q", errOut.String())
	}
	body, _ := os.ReadFile(cfg.Live)
	if !strings.Contains(string(body), "light") {
		t.Errorf("実ファイルを書き換えた: %q", body)
	}
}

func TestClaudePushWithForceOverwritesAndKeepsSecrets(t *testing.T) {
	// **社内設定を消さない。** これが無いと push のたびに社内プラグインが消える
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.SecretDict, "example-corp\n", 0o600)
	writeJSON(t, cfg.Repo, `{"theme":"dark","enabledPlugins":{"q@anthropics":true}}`, 0o644)
	writeJSON(t, cfg.Live, `{"theme":"light","enabledPlugins":{"p@example-corp":true}}`, 0o600)

	w, out, _ := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, true, w); got != Written {
		t.Fatalf("Outcome = %v, want Written（%s）", got, out.String())
	}
	body, _ := os.ReadFile(cfg.Live)
	if !strings.Contains(string(body), "dark") {
		t.Errorf("リポジトリ版で上書きしていない:\n%s", body)
	}
	if !strings.Contains(string(body), "p@example-corp") {
		t.Errorf("社内設定を消した:\n%s", body)
	}
	if !strings.Contains(string(body), "q@anthropics") {
		t.Errorf("リポジトリ側の公開分が入っていない:\n%s", body)
	}
}

func TestClaudePushPreservesLivePermissions(t *testing.T) {
	// **~/.claude/settings.json の 600 を崩さない。**
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Repo, `{"a":1}`, 0o644)
	writeJSON(t, cfg.Live, `{"a":2}`, 0o600)

	w, _, _ := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, true, w); got != Written {
		t.Fatalf("Outcome = %v", got)
	}
	st, err := os.Stat(cfg.Live)
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Mode().Perm(); got != 0o600 {
		t.Errorf("権限 = %o, want 600", got)
	}
}

func TestClaudePushRestoresBrokenLiveOnlyWithForce(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Repo, `{"a":1}`, 0o644)
	writeJSON(t, cfg.Live, `{broken`, 0o600)

	w, _, errOut := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, false, w); got != Failed {
		t.Fatalf("--force なしでは復旧しない: Outcome = %v", got)
	}
	if !strings.Contains(errOut.String(), "正しいJSONではありません") {
		t.Errorf("stderr = %q", errOut.String())
	}

	w2, out2, _ := newIO()
	if got := ClaudePush(context.Background(), realDiff(), cfg, true, w2); got != Restored {
		t.Fatalf("--force で復旧しない: Outcome = %v（%s）", got, out2.String())
	}
	body, _ := os.ReadFile(cfg.Live)
	if !strings.Contains(string(body), `"a": 1`) {
		t.Errorf("復旧していない: %q", body)
	}
}

func TestClaudeStatusIgnoresSecretDifference(t *testing.T) {
	// **機密の有無だけで「差分あり」にしない。** そうしないと status が常に赤くなる
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.SecretDict, "example-corp\n", 0o600)
	writeJSON(t, cfg.Repo, "{\n  \"enabledPlugins\": {},\n  \"theme\": \"dark\"\n}\n", 0o644)
	writeJSON(t, cfg.Live, `{"theme":"dark","enabledPlugins":{"p@example-corp":true}}`, 0o600)

	w, out, _ := newIO()
	if got := ClaudeStatus(context.Background(), realDiff(), cfg, w); got != Unchanged {
		t.Fatalf("Outcome = %v, want Unchanged（%s）", got, out.String())
	}
}

func TestClaudeStatusWritesNothing(t *testing.T) {
	cfg, _ := claudeSetup(t)
	writeJSON(t, cfg.Repo, `{"a":1}`, 0o644)
	writeJSON(t, cfg.Live, `{"a":2}`, 0o600)

	before, _ := os.ReadFile(cfg.Repo)
	w, out, _ := newIO()
	if got := ClaudeStatus(context.Background(), realDiff(), cfg, w); got != WouldWrite {
		t.Fatalf("Outcome = %v, want WouldWrite", got)
	}
	if !strings.Contains(out.String(), "差分あり") {
		t.Errorf("stdout = %q", out.String())
	}
	after, _ := os.ReadFile(cfg.Repo)
	if string(before) != string(after) {
		t.Error("status が書き換えた")
	}
}

// --- Windows 側 ---

func TestWindowsPullPassesThroughINI(t *testing.T) {
	// **.wslconfig は INI なので素通しする。** JSON バリデータに掛けると
	// 通らないうえ、値の導出過程を書いたコメントが消える
	dir := t.TempDir()
	tgt := WindowsTarget{
		Name: "wslconfig",
		Live: filepath.Join(dir, "live.wslconfig"),
		Repo: filepath.Join(dir, "repo.wslconfig"),
		JSON: false,
		Note: "反映には `wsl --shutdown` が必要です。",
	}
	body := "[wsl2]\n# 16GB 機で Windows 側に 4GB 残す実測値\nmemory=12GB\n"
	writeJSON(t, tgt.Live, body, 0o644)

	w, _, _ := newIO()
	if got := WindowsPull(context.Background(), realDiff(), tgt, false, w); got != Written {
		t.Fatalf("Outcome = %v", got)
	}
	got, _ := os.ReadFile(tgt.Repo)
	if string(got) != body {
		t.Errorf("素通しになっていない\n got  %q\n want %q", got, body)
	}
	if !strings.Contains(string(got), "実測値") {
		t.Error("コメントが消えた")
	}
}

func TestWindowsPullNormalizesTerminalJSON(t *testing.T) {
	dir := t.TempDir()
	tgt := WindowsTarget{
		Name: "terminal",
		Live: filepath.Join(dir, "live.json"),
		Repo: filepath.Join(dir, "repo.json"),
		JSON: true,
	}
	writeJSON(t, tgt.Live, `{"b":1,"a":2}`, 0o644)

	w, _, _ := newIO()
	if got := WindowsPull(context.Background(), realDiff(), tgt, false, w); got != Written {
		t.Fatalf("Outcome = %v", got)
	}
	got, _ := os.ReadFile(tgt.Repo)
	if want := "{\n  \"a\": 2,\n  \"b\": 1\n}\n"; string(got) != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestWindowsPullRejectsJSONCInTerminal(t *testing.T) {
	// Windows Terminal は JSONC を許容するので、コメントを書かれると同期が止まる。
	// **止まるのが正しい**（壊れた内容を反対側へ伝播させない）
	dir := t.TempDir()
	tgt := WindowsTarget{Name: "terminal", Live: filepath.Join(dir, "live.json"),
		Repo: filepath.Join(dir, "repo.json"), JSON: true}
	writeJSON(t, tgt.Live, "{\n  // comment\n  \"a\": 1\n}\n", 0o644)

	w, _, errOut := newIO()
	if got := WindowsPull(context.Background(), realDiff(), tgt, false, w); got != Failed {
		t.Fatalf("Outcome = %v, want Failed", got)
	}
	if !strings.Contains(errOut.String(), "正しいJSONではありません") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestWindowsPushIncludesNoteOnWrite(t *testing.T) {
	// 反映に再起動が要ることを伝える（書いただけでは効かない）
	dir := t.TempDir()
	tgt := WindowsTarget{Name: "wslconfig", Live: filepath.Join(dir, "l"),
		Repo: filepath.Join(dir, "r"), Note: "反映には `wsl --shutdown` が必要です。"}
	writeJSON(t, tgt.Repo, "[wsl2]\nmemory=8GB\n", 0o644)

	w, out, _ := newIO()
	if got := WindowsPush(context.Background(), realDiff(), tgt, false, w); got != Created {
		t.Fatalf("Outcome = %v", got)
	}
	if !strings.Contains(out.String(), "wsl --shutdown") {
		t.Errorf("反映方法を案内していない: %q", out.String())
	}
}

func TestWindowsFailsWhenPathUnresolvable(t *testing.T) {
	// /mnt/c を触れない環境（WSL 以外）でパスが解けないときの扱い
	tgt := WindowsTarget{Name: "terminal", Live: "", Repo: filepath.Join(t.TempDir(), "r.json"), JSON: true}
	writeJSON(t, tgt.Repo, `{"a":1}`, 0o644)

	w, _, errOut := newIO()
	if got := WindowsPush(context.Background(), realDiff(), tgt, false, w); got != Failed {
		t.Fatalf("Outcome = %v, want Failed", got)
	}
	if !strings.Contains(errOut.String(), "解決できません") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestWinUserTrimsCRLF(t *testing.T) {
	// cmd.exe は CRLF を返す。**落とさないとパスに \r が混ざる**
	f := execx.NewFake().On("cmd.exe", execx.Result{Stdout: "taro\r\n"})
	if got := WinUser(context.Background(), f); got != "taro" {
		t.Errorf("= %q, want %q", got, "taro")
	}
}

func TestWinUserIsEmptyWhenUnavailable(t *testing.T) {
	f := execx.NewFake().OnError("cmd.exe", os.ErrNotExist)
	if got := WinUser(context.Background(), f); got != "" {
		t.Errorf("= %q, want empty", got)
	}
}

// --- 書き込みの安全性 ---

func TestWriteIfChangedIsAtomicAndKeepsMode(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "f")
	writeJSON(t, dest, "old\n", 0o600)

	changed, err := WriteIfChanged("new\n", dest)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Error("変更したのに false を返した")
	}
	st, _ := os.Stat(dest)
	if got := st.Mode().Perm(); got != 0o600 {
		t.Errorf("権限 = %o, want 600", got)
	}
	// **一時ファイルを残さない**（残ると次回の diff に混ざる）
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".settings-sync.") {
			t.Errorf("一時ファイルが残っている: %s", e.Name())
		}
	}
}

func TestWriteIfChangedSkipsWhenSame(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "f")
	writeJSON(t, dest, "same\n", 0o600)

	before, _ := os.Stat(dest)
	changed, err := WriteIfChanged("same\n", dest)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Error("同一内容なのに書き込んだ")
	}
	after, _ := os.Stat(dest)
	if !before.ModTime().Equal(after.ModTime()) {
		t.Error("同一内容なのに mtime が変わった")
	}
}

func TestWriteIfChangedCreatesParentDir(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "a", "b", "f")
	if _, err := WriteIfChanged("x\n", dest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(dest); err != nil {
		t.Errorf("親ディレクトリを作っていない: %v", err)
	}
}
