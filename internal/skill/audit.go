package skill

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Level は finding の段。
type Level int

const (
	// LOW は人が判断すればよいもの。
	LOW Level = iota
	// MED は注意して読むべきもの。
	MED
	// HIGH は取り込みを止める判断材料になるもの。
	HIGH
)

func (l Level) String() string {
	switch l {
	case HIGH:
		return "HIGH"
	case MED:
		return "MED"
	default:
		return "LOW"
	}
}

// Finding は1件の指摘。
type Finding struct {
	Level   Level
	Path    string // ROOT からの相対パス
	Line    int
	Desc    string
	Excerpt string
}

// AuditResult は監査1回の結果。
type AuditResult struct {
	Findings []Finding
	High     int
	Med      int
	Low      int
}

// Total は findings の総数。
func (r AuditResult) Total() int { return r.High + r.Med + r.Low }

// Summary は要約行（Shell 版と同じ文言）。
func (r AuditResult) Summary() string {
	return fmt.Sprintf("%d findings (%d HIGH, %d MED, %d LOW)", r.Total(), r.High, r.Med, r.Low)
}

// ExitCode は HIGH が1件以上あれば 1。
//
// **取込の可否はここでは決めない。** 平文で書かれた指示型の injection は
// 正規表現では拾い切れないので、vendor 側は audit が 0 でも人の承認を要求する。
func (r AuditResult) ExitCode() int {
	if r.High > 0 {
		return 1
	}
	return 0
}

// rule は正規表現1本ぶんの検査。
type rule struct {
	level Level
	desc  string
	re    *regexp.Regexp
}

// 走査ルール。**順序が出力順になる**ので、Shell 版の並びを保つ。
var rules = []rule{
	{HIGH, "シェル経由のダウンロード実行", regexp.MustCompile(`(curl|wget)[^|]*\|[[:space:]]*(ba|z|fi)?sh`)},
	{HIGH, "eval による動的実行", regexp.MustCompile(`(^|[^[:alnum:]_])eval[[:space:]]`)},
	{HIGH, "base64 デコード", regexp.MustCompile(`base64[[:space:]]+(-d|-D|--decode)`)},
	{HIGH, "機密ファイルへの参照", regexp.MustCompile(`(~/\.aws|\.aws/credentials|\.ssh/|id_rsa|id_ed25519|\.netrc|\.docker/config\.json|gh auth token|aws_secret_access_key)`)},
	{HIGH, "外部への送信", regexp.MustCompile(`(curl[^|]*(--data|-d[[:space:]]|-X[[:space:]]*POST)|(^|[^[:alnum:]_])nc[[:space:]]+-|(^|[^[:alnum:]_])scp[[:space:]])`)},
	{HIGH, "破壊的な操作", regexp.MustCompile(`(rm[[:space:]]+-[a-zA-Z]*[rf]|--no-verify|git[[:space:]]+push[[:space:]]+--force|git[[:space:]]+reset[[:space:]]+--hard)`)},
	{HIGH, "指示の上書きを狙う文言", regexp.MustCompile(`([Ii]gnore[[:space:]]+(all[[:space:]]+)?(previous|prior|above)|[Dd]isregard[[:space:]]+(the[[:space:]]+)?(previous|prior|above)|system[[:space:]]+prompt)`)},
	{HIGH, "ハーネスのタグを騙る記述", regexp.MustCompile(`</?(system-reminder|EXTREMELY_IMPORTANT|EXTREMELY-IMPORTANT|IMPORTANT_INSTRUCTIONS)>`)},
	{MED, ".env への言及", regexp.MustCompile(`(^|[^[:alnum:]])\.env([^[:alnum:]]|$)`)},
	{MED, "設定・フックへの書き込み言及", regexp.MustCompile(`(settings\.json|CLAUDE\.md|AGENTS\.md|hooks/|\.bashrc|\.zshrc|config\.fish|crontab)`)},
	{MED, "実行ビットの付与", regexp.MustCompile(`chmod[[:space:]]+(\+x|[0-7]*7[0-7]*)`)},
	// 不可視・双方向制御文字。**バイト列ではなくコードポイントで書く。**
	// Shell 版は grep -P + \x{...} を使っている（バイト列で書くと GNU grep と
	// ugrep で結果が食い違い、ugrep が3件中1件しか拾わなかった）
	{MED, "不可視・双方向制御文字", regexp.MustCompile(`[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]`)},
}

// allowedHosts は skill が参考リンクとして挙げる先。ここに無いホストは LOW。
var allowedHosts = map[string]bool{
	"github.com":                true,
	"raw.githubusercontent.com": true,
	"gist.github.com":           true,
	"docs.anthropic.com":        true,
	"developer.mozilla.org":     true,
	"react.dev":                 true,
	"nextjs.org":                true,
	"nodejs.org":                true,
	"www.npmjs.com":             true,
	"npmjs.com":                 true,
}

const (
	maxFiles = 100
	maxBytes = 1048576
)

var (
	urlRe          = regexp.MustCompile(`https?://[A-Za-z0-9.-]+`)
	allowedToolsRe = regexp.MustCompile(`^allowed-tools:`)
)

// Audit は skill ディレクトリを走査して findings を返す。
//
// **LLM は一切使わない。** 正規表現で拾えるものだけを機械的に列挙する。
func Audit(ctx context.Context, r execx.Runner, root string) (AuditResult, error) {
	root = strings.TrimSuffix(root, "/")
	st, err := os.Stat(root)
	if err != nil || !st.IsDir() {
		return AuditResult{}, fmt.Errorf("ディレクトリが見つかりません: %s", root)
	}

	all := allFiles(root)
	var texts []string
	for _, f := range all {
		if IsTextFile(f) {
			texts = append(texts, f)
		}
	}

	var res AuditResult
	add := func(level Level, path string, line int, desc, excerpt string) {
		switch level {
		case HIGH:
			res.High++
		case MED:
			res.Med++
		default:
			res.Low++
		}
		res.Findings = append(res.Findings, Finding{level, path, line, desc, excerpt})
	}
	rel := func(p string) string { return strings.TrimPrefix(p, root+"/") }

	// **順序は Shell 版に合わせる。** binary -> rules -> allowed-tools ->
	// html comments -> hosts -> size
	for _, f := range all {
		if IsBinaryFile(f) {
			add(HIGH, rel(f), 0, "非テキストファイル（レビューできない）", "")
		}
	}

	for _, ru := range rules {
		for _, f := range texts {
			eachLine(f, func(no int, line string) {
				if ru.re.MatchString(line) {
					add(ru.level, rel(f), no, ru.desc, line)
				}
			})
		}
	}

	for _, f := range texts {
		if filepath.Base(f) != "SKILL.md" {
			continue
		}
		eachLine(f, func(no int, line string) {
			if !allowedToolsRe.MatchString(line) {
				return
			}
			if strings.Contains(line, "Bash(*)") || strings.Contains(line, "allowed-tools: *") ||
				strings.Contains(line, "WebFetch") || strings.Contains(line, "WebSearch") {
				add(MED, rel(f), no, "allowed-tools が広い", line)
			}
		})
	}

	for _, f := range texts {
		for _, c := range htmlComments(f) {
			add(MED, rel(f), c.start, fmt.Sprintf("HTML コメント内に長文（%d行）", c.lines), "")
		}
	}

	for _, f := range texts {
		for _, h := range firstHostPerFile(f) {
			if allowedHosts[h.host] {
				continue
			}
			add(LOW, rel(f), h.line, "許可リスト外の外部ホスト", h.host)
		}
	}

	if n := len(all); n > maxFiles {
		add(LOW, ".", 0, fmt.Sprintf("ファイル数が多い（%d > %d）", n, maxFiles), "")
	}
	if b := dirBytes(ctx, r, root); b > maxBytes {
		add(LOW, ".", 0, fmt.Sprintf("総バイト数が大きい（%d > %d）", b, maxBytes), "")
	}

	return res, nil
}

// allFiles は走査対象を返す（辞書順）。
// **.git と .vendor.json は自分たちの管理データなので除く。**
func allFiles(root string) []string {
	var out []string
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return fs.SkipDir
			}
			return nil
		}
		if d.Name() == ".vendor.json" {
			return nil
		}
		out = append(out, path)
		return nil
	})
	sort.Strings(out)
	return out
}

// eachLine は1行ずつ渡す（行番号は1始まり）。
func eachLine(path string, fn func(no int, line string)) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer func() { _ = f.Close() }()

	sc := bufio.NewScanner(f)
	// skill には長い行（minified なコード例など）が混ざりうる
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	no := 0
	for sc.Scan() {
		no++
		fn(no, sc.Text())
	}
}

type commentBlock struct {
	start int
	lines int
}

// htmlComments は3行を超える HTML コメントを返す。
//
// **レンダリングされないので人が読み飛ばす一方、モデルには渡る。**
func htmlComments(path string) []commentBlock {
	var out []commentBlock
	inComment := false
	start, n := 0, 0
	eachLine(path, func(no int, line string) {
		if strings.Contains(line, "<!--") {
			inComment = true
			start = no
			n = 0
		}
		if inComment {
			n++
		}
		if strings.Contains(line, "-->") {
			if inComment && n > 3 {
				out = append(out, commentBlock{start, n})
			}
			inComment = false
		}
	})
	return out
}

type hostHit struct {
	line int
	host string
}

// firstHostPerFile はファイル内の外部ホストを初出の1件ずつ返す。
func firstHostPerFile(path string) []hostHit {
	var out []hostHit
	seen := map[string]bool{}
	eachLine(path, func(no int, line string) {
		for _, m := range urlRe.FindAllString(line, -1) {
			host := m
			host = strings.TrimPrefix(host, "https://")
			host = strings.TrimPrefix(host, "http://")
			if seen[host] {
				continue
			}
			seen[host] = true
			out = append(out, hostHit{no, host})
		}
	})
	return out
}

// dirBytes はディレクトリの総バイト数。
//
// **`du -sb` を呼ぶ。** ディレクトリエントリのサイズも含む数え方なので、
// 自前で足すと閾値の意味が変わる。
func dirBytes(ctx context.Context, r execx.Runner, root string) int {
	if r == nil {
		return 0
	}
	res, err := r.Run(ctx, execx.Cmd{Name: "du", Args: []string{"-sb", root}})
	if err != nil || !res.OK() {
		return 0
	}
	fields := strings.Fields(res.Stdout)
	if len(fields) == 0 {
		return 0
	}
	n, err := strconv.Atoi(fields[0])
	if err != nil {
		return 0
	}
	return n
}

// RenderAudit は findings と要約を Shell 版と同じ体裁で書く。
func RenderAudit(w io.Writer, res AuditResult, quiet bool) {
	if !quiet {
		for _, f := range res.Findings {
			fmt.Fprintf(w, "[%s] %s:%d  %s\n", f.Level, f.Path, f.Line, f.Desc)
			if f.Excerpt != "" {
				// 抜粋は現物へ飛ぶ手がかりなので冒頭だけでよい
				fmt.Fprintf(w, "        %s\n", truncate(f.Excerpt, 100))
			}
		}
		fmt.Fprintln(w, "")
	}
	fmt.Fprintln(w, res.Summary())
}

// truncate は先頭 n バイトに切る（`cut -c1-100` 相当）。
//
// **バイトで切るのは Shell 版に合わせているため。** GNU cut の -c は
// マルチバイトを文字として扱わないので、日本語の行は途中で切れて文字化けする。
// 移植では出力を変えない方針なのでここも合わせる（改善は別コミット）。
func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
