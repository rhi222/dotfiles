// repository内の実skillを同じaudit規則で検査し、vendored skillにHigh findingを許さない。
package skill

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// リポジトリに実在する skill 全部を監査して、**壊れずに走り切ること**と
// **既知の状態から外れていないこと**を見る。
//
// 移植時はここで Shell 版と出力を突き合わせていた（vendored 7本 + 自作 skill
// 全部で完全一致を確認済み）。Shell 版が wrapper になった今は比較相手が
// 居ないので、**実在の skill に対する回帰テストへ組み替えてある。**
// 検出ルールそのものは audit_test.go のテーブルが担保する。
//
// **skip して通す作りにしない。** 比較相手が消えた後も skip し続けるテストは
// 何も守らないので、実物を走らせる側に寄せる。
func TestAuditRunsOnAllRealSkills(t *testing.T) {
	if testing.Short() {
		t.Skip("実 skill を全部走査するので -short では飛ばす")
	}
	root := repoRoot(t)

	var dirs []string
	for _, base := range []string{
		filepath.Join(root, ".config", "agents", "skills"),
		filepath.Join(root, ".config", "agents", "skills-vendor"),
		filepath.Join(root, ".config", "claude", "skills"),
		filepath.Join(root, ".config", "codex", "skills"),
	} {
		dirs = append(dirs, skillDirs(t, base)...)
	}
	if len(dirs) == 0 {
		t.Skip("skill が1つも無い")
	}

	checked := 0
	for _, dir := range dirs {
		name := filepath.Base(dir)
		t.Run(name, func(t *testing.T) {
			res, err := Audit(context.Background(), execx.New(), dir)
			if err != nil {
				t.Fatalf("監査が失敗した: %v", err)
			}

			// 走り切っていれば findings の合計は内訳と一致する
			if got := res.Total(); got != res.High+res.Med+res.Low {
				t.Errorf("件数が壊れている: total=%d high=%d med=%d low=%d",
					got, res.High, res.Med, res.Low)
			}

			// 出力が体裁どおりに書けること（要約行は必ず出る）
			var b bytes.Buffer
			RenderAudit(&b, res, false)
			if !strings.Contains(b.String(), res.Summary()) {
				t.Errorf("要約行が出ていない:\n%s", b.String())
			}

			// findings の path は skill 内の相対パス（絶対パスが漏れると
			// 出力が端末ごとに変わる）
			for _, f := range res.Findings {
				if strings.HasPrefix(f.Path, "/") {
					t.Errorf("絶対パスを出している: %+v", f)
				}
				if strings.Contains(f.Path, root) {
					t.Errorf("リポジトリのパスが漏れている: %+v", f)
				}
			}
		})
		checked++
	}
	if checked == 0 {
		t.Fatal("1つも監査していない")
	}
}

// **vendored skill は HIGH が 0 でなければならない。** `skill-vendor.sh status`
// が HIGH を見て [NG] を出す作りなので、ここが崩れると status が赤くなる。
// 実際に取り込んだものが基準を満たし続けていることの回帰。
func TestAuditFindsNoHighInVendoredSkills(t *testing.T) {
	if testing.Short() {
		t.Skip("実 skill を走査するので -short では飛ばす")
	}
	dirs := skillDirs(t, filepath.Join(repoRoot(t), ".config", "agents", "skills-vendor"))
	if len(dirs) == 0 {
		t.Skip("vendored skill が無い")
	}

	for _, dir := range dirs {
		t.Run(filepath.Base(dir), func(t *testing.T) {
			res, err := Audit(context.Background(), execx.New(), dir)
			if err != nil {
				t.Fatal(err)
			}
			if res.High != 0 {
				var b bytes.Buffer
				RenderAudit(&b, res, false)
				t.Errorf("HIGH が %d 件ある（status が [NG] になる）:\n%s", res.High, b.String())
			}
			if res.ExitCode() != 0 {
				t.Errorf("ExitCode = %d, want 0", res.ExitCode())
			}
		})
	}
}

func skillDirs(t *testing.T, base string) []string {
	t.Helper()
	entries, err := os.ReadDir(base)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		// symlink の場合もディレクトリとして辿る（vendored は symlink で入る）
		if st, serr := os.Stat(filepath.Join(base, e.Name())); serr == nil && st.IsDir() {
			out = append(out, filepath.Join(base, e.Name()))
		}
	}
	return out
}

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Dir(filepath.Dir(wd))
}
