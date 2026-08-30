// Package pluginvendor manages reviewed copies of third-party agent plugins.
package pluginvendor

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
	"github.com/rhi222/dotfiles/internal/skill"
)

type Config struct {
	VendorDir string
	CacheDir  string
	Today     string
	AutoYes   bool
}

type Meta struct {
	Origin         string            `json:"origin"`
	Commit         string            `json:"commit"`
	ReviewedCommit string            `json:"reviewed_commit"`
	VendoredAt     string            `json:"vendored_at"`
	Version        string            `json:"version"`
	Files          []string          `json:"files"`
	GeneratedFiles []string          `json:"generated_files"`
	BinarySHA256   map[string]string `json:"binary_sha256"`
	Audit          skill.AuditCount  `json:"audit"`
	License        string            `json:"license"`
}

type IO struct {
	Stdout  io.Writer
	Stderr  io.Writer
	Confirm func(string) bool
}

func (w IO) out() io.Writer {
	if w.Stdout == nil {
		return io.Discard
	}
	return w.Stdout
}

func (w IO) err() io.Writer {
	if w.Stderr == nil {
		return io.Discard
	}
	return w.Stderr
}

func loadMeta(path string) (Meta, error) {
	var meta Meta
	b, err := os.ReadFile(path)
	if err != nil {
		return meta, err
	}
	if err := json.Unmarshal(b, &meta); err != nil {
		return meta, err
	}
	return meta, nil
}

func saveMeta(path string, meta Meta) error {
	b, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func expectedFiles(meta Meta) map[string]bool {
	out := map[string]bool{".vendor.json": true}
	for _, path := range append(append([]string{}, meta.Files...), meta.GeneratedFiles...) {
		out[filepath.Clean(path)] = true
	}
	return out
}

func actualFiles(root string) []string {
	var out []string
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, rerr := filepath.Rel(root, path)
		if rerr == nil {
			out = append(out, rel)
		}
		return nil
	})
	sort.Strings(out)
	return out
}

func fileSHA256(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

// audit ignores binary findings only when the reviewed digest still matches.
func audit(ctx context.Context, r execx.Runner, dir string, meta Meta) (skill.AuditResult, error) {
	res, err := skill.Audit(ctx, r, dir)
	if err != nil {
		return res, err
	}
	filtered := skill.AuditResult{}
	for _, f := range res.Findings {
		if f.Level == skill.HIGH && f.Desc == "非テキストファイル（レビューできない）" {
			want, ok := meta.BinarySHA256[f.Path]
			got, herr := fileSHA256(filepath.Join(dir, f.Path))
			if ok && herr == nil && got == want {
				continue
			}
		}
		filtered.Findings = append(filtered.Findings, f)
		switch f.Level {
		case skill.HIGH:
			filtered.High++
		case skill.MED:
			filtered.Med++
		default:
			filtered.Low++
		}
	}
	return filtered, nil
}

func validateFiles(dir string, meta Meta) []string {
	want := expectedFiles(meta)
	var problems []string
	for _, path := range actualFiles(dir) {
		if !want[path] {
			problems = append(problems, "宣言外のファイル: "+path)
		}
		delete(want, path)
	}
	for path := range want {
		if path != ".vendor.json" {
			problems = append(problems, "不足ファイル: "+path)
		}
	}
	sort.Strings(problems)
	return problems
}

func validateJSONFiles(dir string) []string {
	var problems []string
	for _, path := range actualFiles(dir) {
		if filepath.Ext(path) != ".json" {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, path))
		if err != nil || !json.Valid(b) {
			problems = append(problems, "不正なJSON: "+path)
		}
	}
	return problems
}

func validateManifestVersions(dir string, meta Meta) []string {
	want := meta.Version + "+vendor." + skill.Short(meta.Commit)
	var problems []string
	for _, path := range []string{".claude-plugin/plugin.json", ".codex-plugin/plugin.json"} {
		got, err := manifestVersion(filepath.Join(dir, path))
		if err != nil || got != want {
			problems = append(problems, "manifest versionが記録と違う: "+path)
		}
	}
	return problems
}

func Status(ctx context.Context, r execx.Runner, cfg Config, noNetwork bool, w IO) int {
	entries, err := os.ReadDir(cfg.VendorDir)
	if err != nil {
		fmt.Fprintln(w.out(), "vendored plugin はありません")
		return 0
	}
	rc := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		dir := filepath.Join(cfg.VendorDir, name)
		meta, merr := loadMeta(filepath.Join(dir, ".vendor.json"))
		if merr != nil {
			fmt.Fprintf(w.out(), "[NG] %s: .vendor.json を読めません\n", name)
			rc = 1
			continue
		}
		ok := true
		if meta.Commit != meta.ReviewedCommit {
			fmt.Fprintf(w.out(), "[NG] %s: 未レビュー（commit=%s reviewed=%s）\n", name, skill.Short(meta.Commit), skill.Short(meta.ReviewedCommit))
			ok, rc = false, 1
		}
		for _, problem := range validateFiles(dir, meta) {
			fmt.Fprintf(w.out(), "[NG] %s: %s\n", name, problem)
			ok, rc = false, 1
		}
		for _, problem := range append(validateJSONFiles(dir), validateManifestVersions(dir, meta)...) {
			fmt.Fprintf(w.out(), "[NG] %s: %s\n", name, problem)
			ok, rc = false, 1
		}
		res, aerr := audit(ctx, r, dir, meta)
		if aerr != nil || res.High != 0 || res.Med != meta.Audit.Med || res.Low != meta.Audit.Low {
			if aerr != nil {
				fmt.Fprintf(w.out(), "[NG] %s: audit失敗: %v\n", name, aerr)
			} else {
				fmt.Fprintf(w.out(), "[NG] %s: audit結果が記録と違う（現在 %s）\n", name, res.Summary())
			}
			ok, rc = false, 1
		}
		if !noNetwork {
			if remote := skill.RemoteHead(ctx, r, meta.Origin); remote != "" && remote != meta.Commit {
				fmt.Fprintf(w.out(), "[--] %s: upstream更新あり（%s -> %s）\n", name, skill.Short(meta.Commit), skill.Short(remote))
				fmt.Fprintf(w.out(), "     確認: bash scripts/plugins/vendor.sh update %s\n", name)
			}
		}
		if ok {
			fmt.Fprintf(w.out(), "[OK] %s (%s, reviewed %s)\n", name, skill.Short(meta.Commit), meta.VendoredAt)
		}
	}
	return rc
}

func copyFile(src, dest string) error {
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dest, b, 0o644)
}

func rewriteManifest(path, version string, codex bool) error {
	var body map[string]any
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, &body); err != nil {
		return err
	}
	body["version"] = version
	if codex {
		delete(body, "hooks")
	}
	out, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}

func manifestVersion(path string) (string, error) {
	var body struct {
		Version string `json:"version"`
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	if err := json.Unmarshal(b, &body); err != nil {
		return "", err
	}
	if body.Version == "" {
		return "", fmt.Errorf("manifest versionが空です: %s", path)
	}
	return body.Version, nil
}

func buildCandidate(clone, dest, commit string, meta Meta) error {
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	for _, rel := range meta.Files {
		if err := copyFile(filepath.Join(clone, rel), filepath.Join(dest, rel)); err != nil {
			return fmt.Errorf("%s: %w", rel, err)
		}
	}
	upstreamVersion, err := manifestVersion(filepath.Join(clone, ".claude-plugin", "plugin.json"))
	if err != nil {
		return err
	}
	baseVersion := strings.Split(upstreamVersion, "+")[0]
	version := baseVersion + "+vendor." + skill.Short(commit)
	if err := rewriteManifest(filepath.Join(dest, ".claude-plugin", "plugin.json"), version, false); err != nil {
		return err
	}
	if err := rewriteManifest(filepath.Join(dest, ".codex-plugin", "plugin.json"), version, true); err != nil {
		return err
	}
	return copyFile(filepath.Join(clone, "hooks", "claude-codex-hooks.json"), filepath.Join(dest, "hooks", "hooks.json"))
}

func Update(ctx context.Context, r execx.Runner, cfg Config, name string, w IO) int {
	dest := filepath.Join(cfg.VendorDir, name)
	metaPath := filepath.Join(dest, ".vendor.json")
	meta, err := loadMeta(metaPath)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: vendored plugin が見つかりません: %s\n", name)
		return 1
	}
	clone, err := skill.CloneOrFetch(ctx, r, cfg.CacheDir, meta.Origin)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	commit, err := skill.HeadCommit(ctx, r, clone)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	version, err := manifestVersion(filepath.Join(clone, ".claude-plugin", "plugin.json"))
	if err != nil {
		fmt.Fprintf(w.err(), "Error: upstream versionを読めません: %v\n", err)
		return 1
	}
	meta.Version = strings.Split(version, "+")[0]
	stage, err := os.MkdirTemp("", "plugin-vendor.")
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	defer func() { _ = os.RemoveAll(stage) }()
	candidate := filepath.Join(stage, name)
	if err := buildCandidate(clone, candidate, commit, meta); err != nil {
		fmt.Fprintf(w.err(), "Error: 更新候補を作れません: %v\n", err)
		return 1
	}
	for _, problem := range append(validateFiles(candidate, meta), validateJSONFiles(candidate)...) {
		fmt.Fprintf(w.err(), "Error: 更新候補が不正です: %s\n", problem)
		return 1
	}
	for path := range meta.BinarySHA256 {
		hash, herr := fileSHA256(filepath.Join(candidate, path))
		if herr != nil {
			fmt.Fprintf(w.err(), "Error: binary hashを計算できません: %s\n", path)
			return 1
		}
		meta.BinarySHA256[path] = hash
	}
	res, err := audit(ctx, r, candidate, meta)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: audit失敗: %v\n", err)
		return 1
	}
	skill.RenderAudit(w.err(), res, false)
	if res.High != 0 {
		fmt.Fprintln(w.err(), "Error: HIGH findingがあるため取り込みません")
		return 1
	}
	diff, _ := r.Run(ctx, execx.Cmd{Name: "diff", Args: []string{"-ru", "-x", ".vendor.json", dest, candidate}})
	if strings.TrimSpace(diff.Stdout) == "" {
		meta.Commit, meta.ReviewedCommit, meta.VendoredAt = commit, commit, cfg.Today
		if err := saveMeta(metaPath, meta); err != nil {
			fmt.Fprintf(w.err(), "Error: %v\n", err)
			return 1
		}
		fmt.Fprintf(w.out(), "変更なし: %s のruntimeはupstreamと同一です\n", name)
		return 0
	}
	fmt.Fprintf(w.out(), "=== diff: %s (%s -> %s) ===\n%s\n", name, skill.Short(meta.Commit), skill.Short(commit), diff.Stdout)
	prompt := fmt.Sprintf("この差分を取り込みますか？（HIGH=%d MED=%d LOW=%d）", res.High, res.Med, res.Low)
	approved := cfg.AutoYes
	if !approved && w.Confirm != nil {
		approved = w.Confirm(prompt)
	} else if !approved {
		approved = skill.ConfirmTTY(prompt, w.out())
	}
	if !approved {
		fmt.Fprintln(w.out(), "取り込みを中止しました")
		return 1
	}
	if err := skill.InstallFiles(candidate, dest); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	meta.Commit, meta.ReviewedCommit, meta.VendoredAt = commit, commit, cfg.Today
	meta.Audit = skill.AuditCount{High: res.High, Med: res.Med, Low: res.Low}
	if err := saveMeta(metaPath, meta); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	fmt.Fprintf(w.out(), "-> 更新しました: %s\n", dest)
	fmt.Fprintln(w.out(), "   次: pluginを再installし、新しいsessionで確認する")
	return 0
}
