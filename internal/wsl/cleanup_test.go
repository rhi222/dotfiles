package wsl

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// **現行 store を絶対に消さない**のがこのスクリプトの唯一の本質的判断。
// 消すと node_modules のハードリンクが全部切れる。
func TestSelectUnusedStores(t *testing.T) {
	tests := []struct {
		name       string
		current    string
		all        []string
		wantKeep   []string
		wantRemove []string
	}{
		{
			name:       "現行だけ残す",
			current:    "/h/.local/share/pnpm/store/v3",
			all:        []string{"/h/.local/share/pnpm/store/v3", "/h/.local/share/pnpm/store/v10"},
			wantKeep:   []string{"/h/.local/share/pnpm/store/v3"},
			wantRemove: []string{"/h/.local/share/pnpm/store/v10"},
		},
		{
			// **末尾スラッシュの差で現行を消してはいけない。**
			name:       "末尾スラッシュを無視して比較する",
			current:    "/h/store/v3/",
			all:        []string{"/h/store/v3", "/h/store/v2"},
			wantKeep:   []string{"/h/store/v3"},
			wantRemove: []string{"/h/store/v2"},
		},
		{
			// pnpm store path が取れなかったときは全部が「現行でない」に見えるが、
			// **消してよいと判断しない**わけではない（Shell 版と同じ挙動）
			name:       "現行が取れないと全部が削除候補",
			current:    "",
			all:        []string{"/h/store/v3"},
			wantKeep:   nil,
			wantRemove: []string{"/h/store/v3"},
		},
		{
			name:       "store が無ければ何も返さない",
			current:    "/h/store/v3",
			all:        nil,
			wantKeep:   nil,
			wantRemove: nil,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			keep, remove := SelectUnusedStores(tt.current, tt.all)
			if strings.Join(keep, ",") != strings.Join(tt.wantKeep, ",") {
				t.Errorf("keep = %v, want %v", keep, tt.wantKeep)
			}
			if strings.Join(remove, ",") != strings.Join(tt.wantRemove, ",") {
				t.Errorf("remove = %v, want %v", remove, tt.wantRemove)
			}
		})
	}
}

func fakeRunner() *execx.Fake {
	f := execx.NewFake()
	// du / df / command はいくらでも呼ばれる
	for i := 0; i < 40; i++ {
		f.On("du", execx.Result{Stdout: "12M\t/path\n"})
		f.On("df", execx.Result{Stdout: "Filesystem Size Used Avail Use% Mounted on\n/dev/sdc 1T 100G 900G 10% /\n"})
	}
	return f
}

func run(t *testing.T, cfg Config, f *execx.Fake) (string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	Run(context.Background(), f, cfg, IO{Stdout: &out, Stderr: &errOut})
	return out.String(), errOut.String()
}

func TestRunDryRunDeletesNothing(t *testing.T) {
	home := t.TempDir()
	target := filepath.Join(home, ".cache", "puppeteer")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "x"), []byte("y"), 0o644); err != nil {
		t.Fatal(err)
	}

	out, _ := run(t, Config{Home: home}, fakeRunner())

	if !strings.Contains(out, "DRY-RUN") {
		t.Errorf("モード表示が無い: %q", out)
	}
	if !strings.Contains(out, "(dry-run: 削除しません)") {
		t.Errorf("削除しないと言っていない: %q", out)
	}
	if _, err := os.Stat(target); err != nil {
		t.Error("dry-run なのに削除した")
	}
	if !strings.Contains(out, "これは dry-run です") {
		t.Errorf("末尾の案内が無い: %q", out)
	}
}

func TestRunExecuteDeletesTargets(t *testing.T) {
	home := t.TempDir()
	target := filepath.Join(home, ".cache", "ms-playwright")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatal(err)
	}

	out, _ := run(t, Config{Home: home, Execute: true}, fakeRunner())

	if !strings.Contains(out, "EXECUTE") {
		t.Errorf("モード表示が無い: %q", out)
	}
	if _, err := os.Stat(target); err == nil {
		t.Error("削除していない")
	}
	if !strings.Contains(out, "削除した項目") {
		t.Errorf("削除した項目を出していない: %q", out)
	}
	if !strings.Contains(out, "playwright cache") {
		t.Errorf("何を削除したか出していない: %q", out)
	}
}

func TestRunSkipsMissingPaths(t *testing.T) {
	// **無いものは異常ではない。** その道具を使っていない端末では単に無い
	out, _ := run(t, Config{Home: t.TempDir()}, fakeRunner())
	if !strings.Contains(out, "[skip] puppeteer cache: 見つかりません") {
		t.Errorf("skip の理由を出していない: %q", out)
	}
}

func TestRunNeverTouchesDevEnvironment(t *testing.T) {
	// **開発環境の本体は触らない。** 消すと再構築に時間がかかるものを守る
	home := t.TempDir()
	protected := []string{".cargo", ".rustup", "go", ".local/share/mise", ".config/nvim", ".claude"}
	for _, rel := range protected {
		p := filepath.Join(home, rel)
		if err := os.MkdirAll(p, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(p, "keep"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	run(t, Config{Home: home, Execute: true}, fakeRunner())

	for _, rel := range protected {
		if _, err := os.Stat(filepath.Join(home, rel, "keep")); err != nil {
			t.Errorf("%s を消した", rel)
		}
	}
}

func TestRunKeepsCurrentPnpmStore(t *testing.T) {
	home := t.TempDir()
	root := filepath.Join(home, ".local/share/pnpm/store")
	cur := filepath.Join(root, "v10")
	old := filepath.Join(root, "v3")
	for _, d := range []string{cur, old} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	f := fakeRunner()
	f.On("command", execx.Result{}) // npm
	f.On("command", execx.Result{}) // uv
	f.On("command", execx.Result{}) // pip
	f.On("command", execx.Result{}) // pnpm
	f.On("npm", execx.Result{})
	f.On("uv", execx.Result{})
	f.On("pip", execx.Result{})
	f.On("pnpm", execx.Result{Stdout: cur + "\n"})

	out, _ := run(t, Config{Home: home, Execute: true}, f)

	if _, err := os.Stat(cur); err != nil {
		t.Error("**現行 store を消した**（node_modules のリンクが全部切れる）")
	}
	if _, err := os.Stat(old); err == nil {
		t.Error("未使用 store を消していない")
	}
	if !strings.Contains(out, "[keep] v10: 現行 store のため保持") {
		t.Errorf("保持したことを出していない: %q", out)
	}
}

func TestRunSkipsPnpmWhenCommandMissing(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".local/share/pnpm/store/v3"), 0o755); err != nil {
		t.Fatal(err)
	}

	// command -v が全部失敗する Runner（pnpm が無い端末）
	f := execx.NewFake()
	for i := 0; i < 40; i++ {
		f.On("du", execx.Result{Stdout: "1M\t/p\n"})
		f.On("df", execx.Result{Stdout: "x\n"})
		f.On("command", execx.Result{ExitCode: 1})
	}
	// lookPath も外す（テスト用の差し替え）
	orig := lookPath
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	defer func() { lookPath = orig }()

	out, _ := run(t, Config{Home: home, Execute: true}, f)

	if !strings.Contains(out, "[skip] pnpm コマンドが無いためスキップ") {
		t.Errorf("skip していない: %q", out)
	}
	// **コマンドが無いのに store を消してはいけない**（現行が判定できない）
	if _, err := os.Stat(filepath.Join(home, ".local/share/pnpm/store/v3")); err != nil {
		t.Error("pnpm が無いのに store を消した")
	}
}

func TestRunShowsVhdxGuidance(t *testing.T) {
	// **中で削除しても ext4.vhdx は自動では縮まない。** 手順を出さないと
	// 「掃除したのにディスクが空かない」で終わる
	out, _ := run(t, Config{Home: t.TempDir()}, fakeRunner())
	for _, want := range []string{"ext4.vhdx", "wsl --shutdown", "compact vdisk"} {
		if !strings.Contains(out, want) {
			t.Errorf("案内に %q が無い", want)
		}
	}
}

func TestRunNoColorWhenNotTTY(t *testing.T) {
	out, _ := run(t, Config{Home: t.TempDir()}, fakeRunner())
	if strings.Contains(out, "\x1b[") {
		t.Errorf("TTY でないのに ANSI を出した: %q", out)
	}
}
