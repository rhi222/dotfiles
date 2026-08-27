package skill

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// VendorIO は vendoring の入出力。
type VendorIO struct {
	Stdout io.Writer
	Stderr io.Writer
	// Confirm は承認を取る。nil なら TTY から読む。
	Confirm func(prompt string) bool
}

func (w VendorIO) out() io.Writer {
	if w.Stdout == nil {
		return io.Discard
	}
	return w.Stdout
}

func (w VendorIO) err() io.Writer {
	if w.Stderr == nil {
		return io.Discard
	}
	return w.Stderr
}

// ConfirmTTY は /dev/tty から y/N を読む。
//
// **プロンプトを stdin から読まない。** vendoring は他のコマンドから
// パイプで呼ばれることがあり、stdin が塞がっていると承認を取り損なう。
func ConfirmTTY(prompt string, w io.Writer) bool {
	tty, err := os.Open("/dev/tty")
	if err != nil {
		return false
	}
	defer func() { _ = tty.Close() }()

	fmt.Fprintf(w, "%s [y/N] ", prompt)
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

func (w VendorIO) confirm(prompt string, autoYes bool) bool {
	if autoYes {
		fmt.Fprintf(w.out(), "%s -> 自動承認 (SKILL_VENDOR_YES=1)\n", prompt)
		return true
	}
	if w.Confirm != nil {
		return w.Confirm(prompt)
	}
	return ConfirmTTY(prompt, w.out())
}

// runAudit は audit を走らせ、findings を stderr へ出して件数を返す。
//
// **人向けの findings は stderr へ回す。** Shell 版がそうしているのは、
// stdout に混ぜると件数を読む側が findings の行を拾ってしまうため。
func runAudit(ctx context.Context, r execx.Runner, dir string, w VendorIO) (AuditResult, error) {
	res, err := Audit(ctx, r, dir)
	if err != nil {
		return res, err
	}
	RenderAudit(w.err(), res, false)
	return res, nil
}

// VendorAdd は skill を新しく取り込む。
func VendorAdd(ctx context.Context, r execx.Runner, cfg VendorConfig, spec, subPath, name string, w VendorIO) int {
	origin, err := ResolveOrigin(spec)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}

	clone, err := CloneOrFetch(ctx, r, cfg.CacheDir, origin)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: clone/fetch に失敗しました: %s\n", origin)
		return 1
	}

	src := clone
	if subPath == "." {
		if name == "" {
			name = strings.TrimSuffix(filepath.Base(origin), ".git")
		}
	} else {
		src = filepath.Join(clone, subPath)
		if name == "" {
			name = filepath.Base(subPath)
		}
	}

	if perr := Preflight(cfg, src, name); perr != nil {
		reportPreflight(w, perr)
		return 1
	}

	commit, err := HeadCommit(ctx, r, clone)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}

	fmt.Fprintf(w.out(), "=== audit: %s (%s @ %s) ===\n", name, origin, Short(commit))
	res, aerr := runAudit(ctx, r, src, w)
	if aerr != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", aerr)
		return 1
	}
	fmt.Fprintln(w.out(), "")

	prompt := fmt.Sprintf("この内容で取り込みますか？（HIGH=%d MED=%d LOW=%d。findings が 0 でも本文は目で読んでください）",
		res.High, res.Med, res.Low)
	if !w.confirm(prompt, cfg.AutoYes) {
		fmt.Fprintln(w.out(), "取り込みを中止しました")
		return 1
	}

	dest := filepath.Join(cfg.VendorDir, name)
	if err := os.MkdirAll(cfg.VendorDir, 0o755); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	if err := InstallFiles(src, dest); err != nil {
		fmt.Fprintf(w.err(), "Error: コピーに失敗しました: %v\n", err)
		return 1
	}
	CopyLicense(clone, src, dest, w.err())
	if err := SaveMeta(filepath.Join(dest, ".vendor.json"), VendorMeta{
		Origin:         origin,
		SubPath:        subPath,
		Commit:         commit,
		VendoredAt:     cfg.Today,
		ReviewedCommit: commit,
		Audit:          AuditCount{res.High, res.Med, res.Low},
		License:        DetectLicense(dest),
	}); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}

	fmt.Fprintf(w.out(), "-> 取り込みました: %s\n", dest)
	fmt.Fprintln(w.out(), "   次: ./dotfilesLink.sh でリンクを張り、git diff を見てコミットする")
	return 0
}

func reportPreflight(w VendorIO, err error) {
	var pe *PreflightError
	if e, ok := err.(*PreflightError); ok {
		pe = e
	} else {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return
	}
	fmt.Fprintf(w.err(), "Error: %s\n", pe.Msg)
	if pe.Detail != "" {
		fmt.Fprintln(w.err(), pe.Detail)
	}
}

// VendorUpdate は取込済みの skill を upstream に追随させる。
func VendorUpdate(ctx context.Context, r execx.Runner, cfg VendorConfig, name string, w VendorIO) int {
	dest := filepath.Join(cfg.VendorDir, name)
	jsonPath := filepath.Join(dest, ".vendor.json")
	meta, err := LoadMeta(jsonPath)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: vendored skill が見つかりません: %s\n", name)
		return 1
	}

	clone, err := CloneOrFetch(ctx, r, cfg.CacheDir, meta.Origin)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: clone/fetch に失敗しました: %s\n", meta.Origin)
		return 1
	}

	src := clone
	if meta.SubPath != "." {
		src = filepath.Join(clone, meta.SubPath)
	}
	if st, serr := os.Stat(src); serr != nil || !st.IsDir() {
		fmt.Fprintf(w.err(), "Error: upstream から %s が消えています: %s\n", meta.SubPath, meta.Origin)
		return 1
	}

	commit, err := HeadCommit(ctx, r, clone)
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}

	// **置き換え候補を add と同じ手順で一時ディレクトリに組み立ててから diff を取る。**
	// dest には CopyLicense がリポジトリ直下から持ってきた LICENSE が入っている一方、
	// upstream の skill サブディレクトリにはそれが無い。src と直接比べると常に
	// 「LICENSE だけが違う」差分になり、「変更なし」の判定が死ぬ。
	//
	// 置き換える前に diff を取るのは、**未レビューの状態を作業ツリーに作らないため**。
	staged, err := os.MkdirTemp("", "skill-vendor.")
	if err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	defer func() { _ = os.RemoveAll(staged) }()

	stagedSkill := filepath.Join(staged, name)
	if err := InstallFiles(src, stagedSkill); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	CopyLicense(clone, src, stagedSkill, w.err())

	diffRes, _ := r.Run(ctx, execx.Cmd{
		Name: "diff",
		Args: []string{"-ru", "-x", ".git", "-x", ".vendor.json", dest, stagedSkill},
	})
	diffOut := diffRes.Stdout

	if strings.TrimSpace(diffOut) == "" {
		fmt.Fprintf(w.out(),
			"変更なし: %s のファイルは upstream と同一です（%s -> %s はこの skill 以外の変更）\n",
			name, Short(meta.Commit), Short(commit))
		meta.Commit = commit
		meta.ReviewedCommit = commit
		meta.VendoredAt = cfg.Today
		if err := SaveMeta(jsonPath, meta); err != nil {
			fmt.Fprintf(w.err(), "Error: %v\n", err)
			return 1
		}
		fmt.Fprintf(w.out(), "-> commit と reviewed_commit を %s に更新しました\n", Short(commit))
		return 0
	}

	fmt.Fprintf(w.out(), "=== diff: %s (%s -> %s) ===\n", name, Short(meta.Commit), Short(commit))
	fmt.Fprint(w.out(), diffOut)
	fmt.Fprintln(w.out(), "")
	fmt.Fprintf(w.out(), "=== audit: %s (upstream の新しい内容) ===\n", name)
	res, aerr := runAudit(ctx, r, src, w)
	if aerr != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", aerr)
		return 1
	}
	fmt.Fprintln(w.out(), "")

	prompt := fmt.Sprintf("この差分を取り込みますか？（HIGH=%d MED=%d LOW=%d）", res.High, res.Med, res.Low)
	if !w.confirm(prompt, cfg.AutoYes) {
		fmt.Fprintf(w.out(), "取り込みを中止しました（%s は %s のままです）\n", name, Short(meta.Commit))
		return 1
	}

	if err := InstallFiles(src, dest); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	CopyLicense(clone, src, dest, w.err())
	if err := SaveMeta(jsonPath, VendorMeta{
		Origin:         meta.Origin,
		SubPath:        meta.SubPath,
		Commit:         commit,
		VendoredAt:     cfg.Today,
		ReviewedCommit: commit,
		Audit:          AuditCount{res.High, res.Med, res.Low},
		License:        DetectLicense(dest),
	}); err != nil {
		fmt.Fprintf(w.err(), "Error: %v\n", err)
		return 1
	}
	fmt.Fprintf(w.out(), "-> 更新しました: %s\n", dest)
	fmt.Fprintln(w.out(), "   次: git diff を見てコミットする")
	return 0
}

// VendorStatus は取込済み skill を点検する。
func VendorStatus(ctx context.Context, r execx.Runner, cfg VendorConfig, noNetwork bool, w VendorIO) int {
	if st, err := os.Stat(cfg.VendorDir); err != nil || !st.IsDir() {
		fmt.Fprintf(w.out(), "vendored skill はありません（%s が無い）\n", cfg.VendorDir)
		return 0
	}

	names := ListVendored(cfg.VendorDir)
	if len(names) == 0 {
		fmt.Fprintln(w.out(), "vendored skill はありません")
		return 0
	}

	rc := 0
	for _, name := range names {
		dir := filepath.Join(cfg.VendorDir, name)
		jsonPath := filepath.Join(dir, ".vendor.json")
		meta, err := LoadMeta(jsonPath)
		if err != nil {
			fmt.Fprintf(w.out(), "[NG] %s: .vendor.json が無い\n", name)
			rc = 1
			continue
		}

		ok := true
		if meta.Commit != meta.ReviewedCommit {
			fmt.Fprintf(w.out(), "[NG] %s: 未レビュー（commit=%s reviewed=%s）\n",
				name, Short(meta.Commit), Short(meta.ReviewedCommit))
			rc = 1
			ok = false
		}

		res, aerr := Audit(ctx, r, dir)
		if aerr == nil && res.High != 0 {
			fmt.Fprintf(w.out(), "[NG] %s: audit に HIGH が %d 件ある\n", name, res.High)
			rc = 1
			ok = false
		}

		if !noNetwork {
			if remote := RemoteHead(ctx, r, meta.Origin); remote != "" && remote != meta.Commit {
				fmt.Fprintf(w.out(), "[--] %s: upstream の HEAD が違う（%s -> %s）\n",
					name, Short(meta.Commit), Short(remote))
				fmt.Fprintf(w.out(), "     確認: bash scripts/skills/vendor.sh update %s\n", name)
			}
		}

		for _, lc := range CheckLiveDirs(cfg.LiveDirs, cfg.VendorDir, name) {
			fmt.Fprintf(w.out(), "[NG] %s: %s\n", name, lc.Problem)
			if lc.Recovery != "" {
				fmt.Fprintf(w.out(), "     復旧: %s\n", lc.Recovery)
			}
			rc = 1
			ok = false
		}

		if ok {
			fmt.Fprintf(w.out(), "[OK] %s (%s, reviewed %s)\n", name, Short(meta.Commit), meta.VendoredAt)
		}
	}
	return rc
}

// VendorList は取込済み skill を一覧する。
func VendorList(cfg VendorConfig, w VendorIO) int {
	if st, err := os.Stat(cfg.VendorDir); err != nil || !st.IsDir() {
		fmt.Fprintln(w.out(), "vendored skill はありません")
		return 0
	}

	fmt.Fprintf(w.out(), "%-32s %-10s %-12s %s\n", "NAME", "LICENSE", "VENDORED_AT", "ORIGIN")
	for _, name := range ListVendored(cfg.VendorDir) {
		meta, err := LoadMeta(filepath.Join(cfg.VendorDir, name, ".vendor.json"))
		if err != nil {
			fmt.Fprintf(w.out(), "%-32s %-10s %-12s %s\n", name, "?", "?", "(.vendor.json が無い)")
			continue
		}
		fmt.Fprintf(w.out(), "%-32s %-10s %-12s %s\n", name, meta.License, meta.VendoredAt, meta.Origin)
	}
	return 0
}
