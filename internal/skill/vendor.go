package skill

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// VendorConfig は vendoring1回分の設定。
type VendorConfig struct {
	// VendorDir は取込先（既定 <repo>/.config/agents/skills-vendor）。
	VendorDir string
	// CacheDir は clone のキャッシュ。
	CacheDir string
	// SelfSkills は共用の自作 skill の場所（名前衝突の検査に使う）。
	SelfSkills string
	// AdditionalSelfSkills は agent 固有の自作 skill の場所。
	AdditionalSelfSkills []string
	// LiveDirs は symlink が張られる先（~/.claude/skills など）。
	LiveDirs []string
	// Today は vendored_at に入れる日付。
	Today string
	// AutoYes は承認プロンプトを自動 yes にする（テスト専用）。
	AutoYes bool
}

// VendorMeta は .vendor.json の内容。
type VendorMeta struct {
	Origin         string     `json:"origin"`
	SubPath        string     `json:"sub_path"`
	Commit         string     `json:"commit"`
	VendoredAt     string     `json:"vendored_at"`
	ReviewedCommit string     `json:"reviewed_commit"`
	Audit          AuditCount `json:"audit"`
	License        string     `json:"license"`
}

// AuditCount は取込時の findings 件数。
type AuditCount struct {
	High int `json:"high"`
	Med  int `json:"med"`
	Low  int `json:"low"`
}

// ResolveOrigin は spec を git URL へ解決する。
//
// owner/repo 形式なら GitHub の URL に組み立てる。それ以外は git URL として
// そのまま使う。**先頭が / ./ ../ のものはローカルパス**で、テストが
// `git init --bare` したローカルディレクトリを origin にする（ネットワークに
// 出ないため）ので、owner/repo と誤認させずに素通しする。
func ResolveOrigin(spec string) (string, error) {
	switch {
	case strings.HasPrefix(spec, "/"), strings.HasPrefix(spec, "./"),
		strings.HasPrefix(spec, "../"), strings.Contains(spec, "://"),
		scpLike(spec):
		return spec, nil
	case strings.Contains(spec, "/"):
		return fmt.Sprintf("https://github.com/%s.git", spec), nil
	default:
		return "", fmt.Errorf("owner/repo か git URL を渡してください: %s", spec)
	}
}

// scpLike は `git@host:path` 形式か。
func scpLike(s string) bool {
	at := strings.Index(s, "@")
	if at < 0 {
		return false
	}
	return strings.Contains(s[at:], ":")
}

var slugUnsafe = regexp.MustCompile(`[^A-Za-z0-9._-]`)

// CachePath は origin に対応するキャッシュ先を返す。
func CachePath(cacheDir, origin string) string {
	slug := origin
	slug = strings.TrimPrefix(slug, "https://")
	slug = strings.TrimPrefix(slug, "http://")
	slug = strings.TrimPrefix(slug, "git@")
	slug = strings.Replace(slug, ":", "/", 1)
	slug = strings.TrimSuffix(slug, ".git")
	slug = slugUnsafe.ReplaceAllString(slug, "__")
	return filepath.Join(cacheDir, slug)
}

// DetectLicense は同梱ライセンスの種類を判定する。
func DetectLicense(dir string) string {
	for _, name := range []string{"LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING"} {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		body := strings.ToLower(string(b))
		switch {
		case strings.Contains(body, "mit license"):
			return "MIT"
		case strings.Contains(body, "apache license"):
			return "Apache-2.0"
		case strings.Contains(body, "gnu general public"):
			return "GPL"
		default:
			return "unknown"
		}
	}
	return "none"
}

// LoadMeta は .vendor.json を読む。
func LoadMeta(path string) (VendorMeta, error) {
	var m VendorMeta
	b, err := os.ReadFile(path)
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(b, &m); err != nil {
		return m, err
	}
	return m, nil
}

// SaveMeta は .vendor.json を書く（キー順は Canonical と同じ辞書順）。
func SaveMeta(path string, m VendorMeta) error {
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

// LiveCheck は live dir 1件の点検結果。
type LiveCheck struct {
	Path string
	// Problem は問題の説明（空なら問題なし）。
	Problem string
	// Recovery は復旧手順（あれば）。
	Recovery string
}

// CheckLiveDirs は vendored skill が実際に有効になっているかを見る。
//
// **preflight は add のときだけ走るので、取込後にここを見る場所が無かった。**
// gh skill が先に入れた実ディレクトリが残っていると symlink が張られず、
// Claude は古い gh 版を読み続ける。それでも .vendor.json は正しいので status は
// [OK] を返していた（実際に6本がこの状態だった）。
//
// **無いことは異常ではない**（dotfilesLink.sh 未実行、その agent を使っていない端末）。
func CheckLiveDirs(liveDirs []string, vendorDir, name string) []LiveCheck {
	var out []LiveCheck
	want, _ := filepath.EvalSymlinks(filepath.Join(vendorDir, name))

	for _, base := range liveDirs {
		live := filepath.Join(base, name)
		fi, err := os.Lstat(live)
		if err != nil {
			continue // 無いのは異常ではない
		}
		if fi.Mode()&os.ModeSymlink != 0 {
			target, _ := filepath.EvalSymlinks(live)
			if target != want {
				out = append(out, LiveCheck{
					Path:    live,
					Problem: fmt.Sprintf("%s が vendored を指していません（-> %s）", live, target),
				})
			}
			continue
		}
		if fi.IsDir() {
			out = append(out, LiveCheck{
				Path:     live,
				Problem:  fmt.Sprintf("%s が実ディレクトリです（vendored が読まれていません）", live),
				Recovery: "その実体を退避してから ./dotfilesLink.sh",
			})
		}
	}
	return out
}

// PreflightError は取込前の門前払いの理由。
type PreflightError struct {
	Msg string
	// Detail は複数行の補足（非テキストファイルの一覧など）。
	Detail string
}

func (e *PreflightError) Error() string { return e.Msg }

// Preflight は取込前の門前払い。**ここを通ってからでないと1バイトもコピーしない。**
func Preflight(cfg VendorConfig, src, name string) error {
	if _, err := os.Stat(filepath.Join(src, "SKILL.md")); err != nil {
		return &PreflightError{Msg: fmt.Sprintf("SKILL.md が見つかりません: %s", src)}
	}

	for _, root := range append([]string{cfg.SelfSkills}, cfg.AdditionalSelfSkills...) {
		if st, err := os.Stat(filepath.Join(root, name)); err == nil && st.IsDir() {
			return &PreflightError{
				Msg: fmt.Sprintf("自作 skill と名前が衝突しています: %s",
					filepath.Join(root, name)),
			}
		}
	}

	// **gh skill が入れた実体が残っていると symlink が張れず、古い実体が
	// 読まれ続ける。** 取り込む前に気付けるようにする。
	for _, base := range cfg.LiveDirs {
		live := filepath.Join(base, name)
		fi, err := os.Lstat(live)
		if err != nil || fi.Mode()&os.ModeSymlink != 0 || !fi.IsDir() {
			continue
		}
		return &PreflightError{
			Msg: fmt.Sprintf("%s が実ディレクトリとして存在します", live),
			Detail: fmt.Sprintf(`  gh skill が入れた実体が残っていると symlink が張れず、古い実体が読まれ続けます。
  先に消してください:
    rm -rf ~/.claude/skills/%s ~/.codex/skills/%s ~/.agents/skills/%s`, name, name, name),
		}
	}

	// 非テキストファイルは読んでレビューできないので入れない。
	// **判定は audit と一致させる**（IsBinaryFile を共有している）。
	var bin []string
	for _, f := range allFiles(src) {
		if IsBinaryFile(f) {
			bin = append(bin, "  "+strings.TrimPrefix(f, src+"/"))
		}
	}
	if len(bin) > 0 {
		sort.Strings(bin)
		return &PreflightError{
			Msg:    "非テキストファイルが含まれています（レビューできないため取り込みません）",
			Detail: strings.Join(bin, "\n"),
		}
	}
	return nil
}

// InstallFiles は src の内容を dest へ置き換える。
//
// **.git は持ち込まず、実行ビットは落とす。** skill は読まれるだけのもので、
// 実行される必要が無い。
func InstallFiles(src, dest string) error {
	if err := os.RemoveAll(dest); err != nil {
		return err
	}
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	return filepath.Walk(src, func(path string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, rerr := filepath.Rel(src, path)
		if rerr != nil {
			return rerr
		}
		if rel == "." {
			return nil
		}
		if fi.IsDir() {
			if fi.Name() == ".git" {
				return filepath.SkipDir
			}
			return os.MkdirAll(filepath.Join(dest, rel), 0o755)
		}
		if !fi.Mode().IsRegular() {
			return nil
		}
		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		out := filepath.Join(dest, rel)
		if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
			return err
		}
		// 実行ビットを落とす（a-x 相当）
		return os.WriteFile(out, b, fi.Mode().Perm()&0o666)
	})
}

// CopyLicense は upstream 側のライセンスを同梱する。
// skill 直下に無ければリポジトリ直下から拾う。
func CopyLicense(clone, src, dest string, w io.Writer) {
	names := []string{"LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING"}
	for _, n := range names {
		if _, err := os.Stat(filepath.Join(src, n)); err == nil {
			return // skill 直下にあるならそれを使う
		}
	}
	for _, n := range names {
		b, err := os.ReadFile(filepath.Join(clone, n))
		if err != nil {
			continue
		}
		if werr := os.WriteFile(filepath.Join(dest, "LICENSE"), b, 0o644); werr == nil {
			return
		}
	}
	fmt.Fprintln(w, "[WARN] upstream に LICENSE が見つかりませんでした")
}

// CloneOrFetch は clone か fetch で最新にして、clone 先のパスを返す。
func CloneOrFetch(ctx context.Context, r execx.Runner, cacheDir, origin string) (string, error) {
	dir := CachePath(cacheDir, origin)
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return "", err
	}
	if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
		res, rerr := r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", dir, "fetch", "--quiet", "--depth", "1", "origin", "HEAD"},
		})
		if rerr != nil || !res.OK() {
			return "", fmt.Errorf("fetch に失敗しました: %s", origin)
		}
		res, rerr = r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", dir, "reset", "--quiet", "--hard", "FETCH_HEAD"},
		})
		if rerr != nil || !res.OK() {
			return "", fmt.Errorf("reset に失敗しました: %s", origin)
		}
		return dir, nil
	}
	res, rerr := r.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"clone", "--quiet", "--depth", "1", origin, dir},
	})
	if rerr != nil || !res.OK() {
		return "", fmt.Errorf("clone に失敗しました: %s", origin)
	}
	return dir, nil
}

// HeadCommit は clone の HEAD を返す。
func HeadCommit(ctx context.Context, r execx.Runner, dir string) (string, error) {
	res, err := r.Run(ctx, execx.Cmd{Name: "git", Args: []string{"-C", dir, "rev-parse", "HEAD"}})
	if err != nil || !res.OK() {
		return "", fmt.Errorf("HEAD を取得できません: %s", dir)
	}
	return strings.TrimSpace(res.Stdout), nil
}

// RemoteHead は upstream の HEAD を返す（取れなければ空）。
func RemoteHead(ctx context.Context, r execx.Runner, origin string) string {
	res, err := r.Run(ctx, execx.Cmd{Name: "git", Args: []string{"ls-remote", origin, "HEAD"}})
	if err != nil || !res.OK() {
		return ""
	}
	fields := strings.Fields(res.Stdout)
	if len(fields) == 0 {
		return ""
	}
	return fields[0]
}

// Short は commit の先頭7文字。
func Short(s string) string {
	if len(s) > 7 {
		return s[:7]
	}
	return s
}

// ListVendored は取込済み skill の名前を返す（辞書順）。
func ListVendored(vendorDir string) []string {
	entries, err := os.ReadDir(vendorDir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out
}
