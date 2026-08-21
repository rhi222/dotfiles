package docker

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/rhi222/dotfiles/internal/execx"
)

// SchemaCurrent はキャッシュのスキーマ版。
//
// **running[] の列を増やしたらここを上げる。** 古い版のキャッシュは TTL 内でも
// stale 扱いにして作り直す（種別列を持たないキャッシュを読んでいる間は orphan
// 件数を出せないため）。
const SchemaCurrent = 2

// Kind はコンテナの由来。
type Kind string

const (
	// Standalone は compose 管理外（docker run 由来）。
	// **レシピが docker 側に一切残らず、--rm 付きなら停止＝即削除になる。**
	Standalone Kind = "standalone"
	// Orphan は compose 管理だが working_dir が消えている。確実な停止候補。
	Orphan Kind = "orphan"
	// Compose は compose 管理で working_dir が存在する。up で戻せる。
	Compose Kind = "compose"
)

// ContainerKind はコンテナの由来を判定する。
//
// **判定順が要点。compose_dir が空のときは orphan にせず compose に倒す。**
// orphan は削除を伴う `docker compose down` を案内する側なので、孤児だと
// 証明できないものを孤児扱いしてはいけない。
func ContainerKind(project, dir string, dirExists func(string) bool) Kind {
	if project == "" {
		return Standalone
	}
	if dir != "" && !dirExists(dir) {
		return Orphan
	}
	return Compose
}

// DirExists は実ファイルシステムでディレクトリの有無を見る。
func DirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// Container は稼働中コンテナ1件。
type Container struct {
	Name           string `json:"name"`
	Image          string `json:"image"`
	UptimeSeconds  int64  `json:"uptime_seconds"`
	ComposeProject string `json:"compose_project"`
	ComposeDir     string `json:"compose_dir"`
	// AutoRemove は --rm 付きで起動されたか。**停止＝削除になる**ので表示で警告する。
	AutoRemove bool `json:"auto_remove"`
}

// DFEntry は `docker system df --format json` の1行。
type DFEntry struct {
	Type        string `json:"Type"`
	TotalCount  string `json:"TotalCount"`
	Active      string `json:"Active"`
	Size        string `json:"Size"`
	Reclaimable string `json:"Reclaimable"`
}

// Stats はキャッシュの内容。
type Stats struct {
	GeneratedAt int64       `json:"generated_at"`
	Schema      int         `json:"schema"`
	DF          []DFEntry   `json:"df"`
	Running     []Container `json:"running"`
}

// Config は docker 掃除1回分の設定。
type Config struct {
	// CacheFile はキャッシュの置き場。
	CacheFile string
	// SizeThresholdGB は通知を出す回収可能量の閾値（既定 5）。
	SizeThresholdGB float64
	// UptimeThresholdH は長時間稼働とみなす時間（既定 12）。
	UptimeThresholdH float64
	// CacheTTLH はキャッシュの TTL（既定 6）。
	CacheTTLH float64
	// IgnorePatterns は長時間稼働の集計から除外する名前/イメージのグロブ。
	//
	// **既定は buildx のビルダーだけ。** 常駐させている個別のコンテナは
	// 環境ごとに違うので、除外したいものは利用者が足す。
	IgnorePatterns []string
	// Now は現在時刻（テストで固定する）。
	Now time.Time
}

// DefaultConfig は既定値を埋めた設定を返す。
func DefaultConfig(home string) Config {
	return Config{
		CacheFile:        filepath.Join(home, ".local", "state", "docker-clean", "stats.json"),
		SizeThresholdGB:  5,
		UptimeThresholdH: 12,
		CacheTTLH:        6,
		IgnorePatterns:   []string{"buildx_buildkit_*"},
		Now:              time.Now(),
	}
}

// DFField は指定種別のフィールドを取り出す（無ければ空）。
func (s *Stats) DFField(typ, field string) string {
	for _, e := range s.DF {
		if e.Type != typ {
			continue
		}
		switch field {
		case "TotalCount":
			return e.TotalCount
		case "Active":
			return e.Active
		case "Size":
			return e.Size
		case "Reclaimable":
			return e.Reclaimable
		}
	}
	return ""
}

// ReadStats はキャッシュを読む。無い・壊れているなら false。
func ReadStats(path string) (*Stats, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	var s Stats
	if err := json.Unmarshal(b, &s); err != nil {
		return nil, false
	}
	return &s, true
}

// IsStale はキャッシュが TTL 超か、スキーマが古いか、読めないか。
//
// **スキーマが古ければ TTL 内でも作り直す。** 種別列を持たないキャッシュを
// 読んでいる間は orphan 件数を出せないため、起動時の background 更新に乗せて
// 次回から正しくする。
func IsStale(cfg Config) bool {
	s, ok := ReadStats(cfg.CacheFile)
	if !ok {
		return true
	}
	if s.GeneratedAt <= 0 {
		return true
	}
	if s.Schema != SchemaCurrent {
		return true
	}
	age := cfg.Now.Unix() - s.GeneratedAt
	return age >= int64(cfg.CacheTTLH*3600)
}

// UpdateStats は docker を叩いてキャッシュを書く。
//
// `docker system df` は実測 5.2 秒かかるため、**shell 起動時に同期実行しては
// ならない**。起動時はキャッシュを読むだけにして、更新は background に逃がす。
func UpdateStats(ctx context.Context, r execx.Runner, cfg Config) error {
	if res, err := r.Run(ctx, execx.Cmd{Name: "docker", Args: []string{"info"}}); err != nil || !res.OK() {
		return errDockerUnavailable
	}

	s := Stats{GeneratedAt: cfg.Now.Unix(), Schema: SchemaCurrent}

	res, err := r.Run(ctx, execx.Cmd{
		Name: "docker", Args: []string{"system", "df", "--format", "json"},
	})
	if err != nil || !res.OK() {
		return errDockerUnavailable
	}
	// 1行1オブジェクトの JSONL
	for _, line := range strings.Split(strings.TrimSuffix(res.Stdout, "\n"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var e DFEntry
		if json.Unmarshal([]byte(line), &e) == nil {
			s.DF = append(s.DF, e)
		}
	}

	s.Running = inspectRunning(ctx, r, cfg)
	if s.Running == nil {
		s.Running = []Container{}
	}

	return writeStats(cfg.CacheFile, s)
}

var errDockerUnavailable = &dockerError{"docker が起動していません"}

type dockerError struct{ msg string }

func (e *dockerError) Error() string { return e.msg }

// inspectRunning は稼働中コンテナの情報を集める。
func inspectRunning(ctx context.Context, r execx.Runner, cfg Config) []Container {
	idRes, err := r.Run(ctx, execx.Cmd{Name: "docker", Args: []string{"ps", "-q"}})
	if err != nil || !idRes.OK() {
		return nil
	}
	ids := strings.Fields(idRes.Stdout)
	if len(ids) == 0 {
		return nil
	}

	// **label は種別判定に使う。** `{{index .Config.Labels "..."}}` は Labels が
	// nil でもキーが無くても空文字を返す（`<no value>` にはならない）。
	format := `{{.Name}}|{{.Config.Image}}|{{.State.StartedAt}}` +
		`|{{index .Config.Labels "com.docker.compose.project"}}` +
		`|{{index .Config.Labels "com.docker.compose.project.working_dir"}}` +
		`|{{.HostConfig.AutoRemove}}`

	args := append([]string{"inspect", "--format", format}, ids...)
	res, ierr := r.Run(ctx, execx.Cmd{Name: "docker", Args: args})
	if ierr != nil || !res.OK() {
		return nil
	}

	now := cfg.Now.Unix()
	var out []Container
	for _, line := range strings.Split(strings.TrimSuffix(res.Stdout, "\n"), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		f := strings.Split(line, "|")
		if len(f) < 3 {
			continue
		}
		c := Container{
			Name:  strings.TrimPrefix(f[0], "/"),
			Image: f[1],
		}
		started := parseDockerTime(f[2])
		if started == 0 {
			started = now
		}
		c.UptimeSeconds = now - started
		if len(f) >= 4 {
			c.ComposeProject = f[3]
		}
		if len(f) >= 5 {
			c.ComposeDir = f[4]
		}
		if len(f) >= 6 {
			c.AutoRemove = strings.TrimSpace(f[5]) == "true"
		}
		out = append(out, c)
	}
	return out
}

// parseDockerTime は docker の StartedAt を epoch 秒にする（読めなければ 0）。
func parseDockerTime(s string) int64 {
	s = strings.TrimSpace(s)
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05.999999999Z0700"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.Unix()
		}
	}
	return 0
}

// writeStats はキャッシュを一時ファイル + rename で置き換える。
func writeStats(path string, s Stats) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.Marshal(s)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".stats.*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(append(b, '\n')); err != nil {
		_ = tmp.Close()
		_ = os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(name)
		return err
	}
	if err := os.Chmod(name, 0o644); err != nil {
		_ = os.Remove(name)
		return err
	}
	return os.Rename(name, path)
}

// IsIgnored はコンテナが除外パターンにマッチするか。
//
// **コンテナ名とイメージ名の両方に照合する。** ツールが起動するコンテナは
// 名前が自動生成（suspicious_gagarin 等）で識別できないため、イメージ名側での
// 照合が必須。
func IsIgnored(patterns []string, name, image string) bool {
	for _, p := range patterns {
		if globMatch(p, name) || globMatch(p, image) {
			return true
		}
	}
	return false
}

// globMatch は fish の `string match` と同じ範囲のグロブ（* と ?）で照合する。
//
// **filepath.Match は使わない。** あれは `*` が `/` を跨がないので、
// イメージ名（`ghcr.io/o/r:tag`）のパターンで意図と食い違う。
func globMatch(pattern, s string) bool {
	// 動的計画法で * と ? を評価する
	p, str := []rune(pattern), []rune(s)
	dp := make([][]bool, len(p)+1)
	for i := range dp {
		dp[i] = make([]bool, len(str)+1)
	}
	dp[0][0] = true
	for i := 1; i <= len(p); i++ {
		if p[i-1] == '*' {
			dp[i][0] = dp[i-1][0]
		}
	}
	for i := 1; i <= len(p); i++ {
		for j := 1; j <= len(str); j++ {
			switch p[i-1] {
			case '*':
				dp[i][j] = dp[i-1][j] || dp[i][j-1]
			case '?':
				dp[i][j] = dp[i-1][j-1]
			default:
				dp[i][j] = dp[i-1][j-1] && p[i-1] == str[j-1]
			}
		}
	}
	return dp[len(p)][len(str)]
}

// LongRunning は閾値を超えて稼働しているコンテナを返す。
//
// excluded が真なら「閾値超えだが除外パターンにマッチした」側を返す
// （プレビューの注記用）。
func LongRunning(s *Stats, cfg Config, excluded bool) []Container {
	if s == nil {
		return nil
	}
	thr := int64(cfg.UptimeThresholdH * 3600)
	var out []Container
	for _, c := range s.Running {
		if c.UptimeSeconds <= thr {
			continue
		}
		if IsIgnored(cfg.IgnorePatterns, c.Name, c.Image) == excluded {
			out = append(out, c)
		}
	}
	return out
}

// HumanizeUptime は秒数を「23 hours」形式にする。
func HumanizeUptime(sec int64) string {
	h := sec / 3600
	if h < 24 {
		return strconv.FormatInt(h, 10) + " hours"
	}
	return strconv.FormatInt(h/24, 10) + " days"
}
