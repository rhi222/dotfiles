package docker

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rhi222/dotfiles/internal/execx"
)

// **判定順が要点。compose_dir が空のときは orphan にせず compose に倒す。**
// orphan は削除を伴う `docker compose down` を案内する側なので、孤児だと
// 証明できないものを孤児扱いしてはいけない。
func TestContainerKind(t *testing.T) {
	exists := func(p string) bool { return p == "/live" }

	tests := []struct {
		name         string
		project, dir string
		want         Kind
	}{
		{"label が無ければ standalone", "", "", Standalone},
		{"label が無ければ dir があっても standalone", "", "/live", Standalone},
		{"working_dir が生きていれば compose", "proj", "/live", Compose},
		{"working_dir が消えていれば orphan", "proj", "/gone", Orphan},
		// **証明できないものを孤児扱いしない**
		{"dir が空なら compose に倒す", "proj", "", Compose},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ContainerKind(tt.project, tt.dir, exists); got != tt.want {
				t.Errorf("= %v, want %v", got, tt.want)
			}
		})
	}
}

func TestIsIgnoredMatchesNameAndImage(t *testing.T) {
	// **イメージ名側での照合が必須。** ツールが起動するコンテナは名前が
	// 自動生成（suspicious_gagarin 等）で識別できない
	pats := []string{"buildx_buildkit_*", "ghcr.io/example/*"}

	if !IsIgnored(pats, "buildx_buildkit_default0", "moby/buildkit:latest") {
		t.Error("名前で一致しない")
	}
	if !IsIgnored(pats, "suspicious_gagarin", "ghcr.io/example/tool:v1") {
		t.Error("イメージ名で一致しない")
	}
	if IsIgnored(pats, "myapp", "nginx:latest") {
		t.Error("無関係なものに一致した")
	}
	if IsIgnored(nil, "anything", "anything") {
		t.Error("パターンが無いのに一致した")
	}
}

func TestGlobMatchCrossesSlash(t *testing.T) {
	// **filepath.Match は使わない。** `*` が `/` を跨がないので、
	// イメージ名のパターンで意図と食い違う
	if !globMatch("ghcr.io/*", "ghcr.io/owner/repo:tag") {
		t.Error("* が / を跨いでいない")
	}
	if !globMatch("*buildkit*", "buildx_buildkit_default0") {
		t.Error("前後の * が効いていない")
	}
	if !globMatch("a?c", "abc") {
		t.Error("? が効いていない")
	}
	if globMatch("a?c", "ac") {
		t.Error("? が0文字に一致した")
	}
}

func TestHumanizeUptime(t *testing.T) {
	tests := []struct {
		sec  int64
		want string
	}{
		{0, "0 hours"},
		{3599, "0 hours"},
		{3600, "1 hours"},
		{23 * 3600, "23 hours"},
		{24 * 3600, "1 days"},
		{72 * 3600, "3 days"},
	}
	for _, tt := range tests {
		if got := HumanizeUptime(tt.sec); got != tt.want {
			t.Errorf("HumanizeUptime(%d) = %q, want %q", tt.sec, got, tt.want)
		}
	}
}

// --- キャッシュ ---

func testConfig(t *testing.T) Config {
	t.Helper()
	cfg := DefaultConfig(t.TempDir())
	cfg.CacheFile = filepath.Join(t.TempDir(), "stats.json")
	cfg.Now = time.Unix(1_700_000_000, 0)
	return cfg
}

func writeCache(t *testing.T, path string, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadStatsRejectsBrokenCache(t *testing.T) {
	cfg := testConfig(t)
	if _, ok := ReadStats(cfg.CacheFile); ok {
		t.Error("無いキャッシュを読めたと言った")
	}
	writeCache(t, cfg.CacheFile, "{broken")
	if _, ok := ReadStats(cfg.CacheFile); ok {
		t.Error("壊れたキャッシュを読めたと言った")
	}
}

func TestIsStale(t *testing.T) {
	cfg := testConfig(t)

	// 無い -> stale
	if !IsStale(cfg) {
		t.Error("キャッシュが無いのに stale でない")
	}

	fresh := cfg.Now.Unix() - 60
	writeCache(t, cfg.CacheFile,
		`{"generated_at":`+itoa(fresh)+`,"schema":2,"df":[],"running":[]}`)
	if IsStale(cfg) {
		t.Error("新しいのに stale と言った")
	}

	// TTL 超
	old := cfg.Now.Unix() - int64(cfg.CacheTTLH*3600) - 1
	writeCache(t, cfg.CacheFile,
		`{"generated_at":`+itoa(old)+`,"schema":2,"df":[],"running":[]}`)
	if !IsStale(cfg) {
		t.Error("TTL 超なのに stale でない")
	}

	// **スキーマが古ければ TTL 内でも作り直す。** 種別列を持たないキャッシュを
	// 読んでいる間は orphan 件数を出せない
	writeCache(t, cfg.CacheFile,
		`{"generated_at":`+itoa(fresh)+`,"schema":1,"df":[],"running":[]}`)
	if !IsStale(cfg) {
		t.Error("スキーマが古いのに stale でない")
	}
}

func TestUpdateStatsWritesCache(t *testing.T) {
	cfg := testConfig(t)
	f := execx.NewFake()
	f.On("docker", execx.Result{})                    // info
	f.On("docker", execx.Result{Stdout: dfJSONL})     // system df
	f.On("docker", execx.Result{Stdout: "abc123\n"})  // ps -q
	f.On("docker", execx.Result{Stdout: inspectLine}) // inspect

	if err := UpdateStats(context.Background(), f, cfg); err != nil {
		t.Fatal(err)
	}
	s, ok := ReadStats(cfg.CacheFile)
	if !ok {
		t.Fatal("キャッシュを読めない")
	}
	if s.Schema != SchemaCurrent {
		t.Errorf("Schema = %d, want %d", s.Schema, SchemaCurrent)
	}
	if s.GeneratedAt != cfg.Now.Unix() {
		t.Errorf("GeneratedAt = %d", s.GeneratedAt)
	}
	if len(s.DF) != 4 {
		t.Fatalf("DF = %d 件, want 4: %+v", len(s.DF), s.DF)
	}
	if len(s.Running) != 1 {
		t.Fatalf("Running = %d 件", len(s.Running))
	}
	c := s.Running[0]
	if c.Name != "myapp" {
		t.Errorf("Name = %q（先頭の / を落とす）", c.Name)
	}
	if c.ComposeProject != "proj" || c.ComposeDir != "/work/proj" {
		t.Errorf("label を取れていない: %+v", c)
	}
	if !c.AutoRemove {
		t.Error("AutoRemove を取れていない")
	}
}

func TestUpdateStatsFailsWhenDockerDown(t *testing.T) {
	cfg := testConfig(t)
	f := execx.NewFake().On("docker", execx.Result{ExitCode: 1})
	if err := UpdateStats(context.Background(), f, cfg); err == nil {
		t.Error("docker が落ちているのに成功した")
	}
	if _, ok := ReadStats(cfg.CacheFile); ok {
		t.Error("失敗したのにキャッシュを書いた")
	}
}

func TestUpdateStatsHandlesNoRunningContainers(t *testing.T) {
	// 稼働 0 件のとき running が null にならないこと
	cfg := testConfig(t)
	f := execx.NewFake()
	f.On("docker", execx.Result{})
	f.On("docker", execx.Result{Stdout: dfJSONL})
	f.On("docker", execx.Result{Stdout: "\n"}) // ps -q が空

	if err := UpdateStats(context.Background(), f, cfg); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(cfg.CacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"running":[]`) {
		t.Errorf("running が [] になっていない: %s", b)
	}
}

func TestLongRunningRespectsThresholdAndIgnore(t *testing.T) {
	cfg := testConfig(t)
	cfg.UptimeThresholdH = 12
	cfg.IgnorePatterns = []string{"buildx_buildkit_*"}

	s := &Stats{Running: []Container{
		{Name: "short", Image: "a", UptimeSeconds: 3600},
		{Name: "long", Image: "b", UptimeSeconds: 13 * 3600},
		{Name: "buildx_buildkit_default0", Image: "moby/buildkit", UptimeSeconds: 100 * 3600},
	}}

	got := LongRunning(s, cfg, false)
	if len(got) != 1 || got[0].Name != "long" {
		t.Errorf("= %+v, want [long]", got)
	}
	// 除外側も取れる（プレビューの注記に使う）
	ex := LongRunning(s, cfg, true)
	if len(ex) != 1 || ex[0].Name != "buildx_buildkit_default0" {
		t.Errorf("除外側 = %+v", ex)
	}
}

// --- 通知 ---

// **df の Images Reclaimable を軽掃除の根拠にしてはいけない。** 軽掃除の
// `image prune -f` は dangling だけを消すので、ここを根拠にすると
// 「dclean しても通知が消えない」状態になる（実際になった）。
func TestSplitReclaimableSeparatesImages(t *testing.T) {
	s := &Stats{DF: []DFEntry{
		{Type: "Images", Reclaimable: "10GB"},
		{Type: "Containers", Reclaimable: "1GB"},
		{Type: "Local Volumes", Reclaimable: "2GB"},
		{Type: "Build Cache", Reclaimable: "3GB"},
	}}
	rec := SplitReclaimable(s)
	if rec.Light != 6_000_000_000 {
		t.Errorf("Light = %d, want 6GB（Images を含めない）", rec.Light)
	}
	if rec.Heavy != 16_000_000_000 {
		t.Errorf("Heavy = %d, want 16GB", rec.Heavy)
	}
}

func TestNoticeChoosesCommandMatchingTheAmount(t *testing.T) {
	cfg := testConfig(t)
	cfg.SizeThresholdGB = 5
	exists := func(string) bool { return true }

	// 軽掃除で回収できる量 -> dclean
	light := &Stats{DF: []DFEntry{{Type: "Containers", Reclaimable: "6GB"}}}
	got := Notice(light, cfg, exists)
	if !strings.Contains(got, "6GB 回収可能") || !strings.HasSuffix(got, "→ dclean") {
		t.Errorf("= %q", got)
	}

	// **軽掃除では回収できず、重掃除でしか消えない量 -> dclean -a**
	// ここを間違えると「実行しても通知が消えない」
	heavy := &Stats{DF: []DFEntry{{Type: "Images", Reclaimable: "9GB"}}}
	got = Notice(heavy, cfg, exists)
	if !strings.Contains(got, "未使用 image 中心") {
		t.Errorf("重掃除向けの文言でない: %q", got)
	}
	if !strings.HasSuffix(got, "→ dclean -a") {
		t.Errorf("案内が dclean -a でない: %q", got)
	}
}

func TestNoticeIsEmptyBelowThresholds(t *testing.T) {
	cfg := testConfig(t)
	s := &Stats{DF: []DFEntry{{Type: "Containers", Reclaimable: "1GB"}}}
	if got := Notice(s, cfg, func(string) bool { return true }); got != "" {
		t.Errorf("閾値未満で通知を出した: %q", got)
	}
}

func TestNoticeReportsLongRunningAndOrphan(t *testing.T) {
	cfg := testConfig(t)
	cfg.UptimeThresholdH = 12
	s := &Stats{Running: []Container{
		{Name: "a", UptimeSeconds: 13 * 3600, ComposeProject: "p1", ComposeDir: "/gone"},
		{Name: "b", UptimeSeconds: 20 * 3600, ComposeProject: "p2", ComposeDir: "/live"},
	}}
	exists := func(p string) bool { return p == "/live" }

	got := Notice(s, cfg, exists)
	if !strings.Contains(got, "12h超稼働 2件") {
		t.Errorf("件数が違う: %q", got)
	}
	if !strings.Contains(got, "（orphan 1）") {
		t.Errorf("orphan 件数が無い: %q", got)
	}
	// サイズが閾値未満なら --status を案内する（消すものが無い）
	if !strings.HasSuffix(got, "→ dclean --status") {
		t.Errorf("案内が違う: %q", got)
	}
}

// --- prune のコマンド列 ---

// **volume prune には軽・重どちらでも -a を付けない。** -a なしなら匿名 volume
// だけが対象になり、named volume（DB データ）が守られる。
func TestPruneCommandsNeverUseVolumePruneAll(t *testing.T) {
	for _, mode := range []Mode{Light, Heavy} {
		for _, args := range PruneCommands(mode, nil) {
			joined := strings.Join(args, " ")
			if strings.HasPrefix(joined, "volume prune") && strings.Contains(joined, "-a") {
				t.Errorf("mode=%v で volume prune -a を使っている: %q", mode, joined)
			}
		}
	}
}

func TestPruneCommandsByMode(t *testing.T) {
	light := flatten(PruneCommands(Light, nil))
	if !contains(light, "image prune -f") {
		t.Errorf("軽で dangling のみの image prune が無い: %v", light)
	}
	if contains(light, "image prune -a -f") {
		t.Errorf("軽で -a を使っている: %v", light)
	}
	if !contains(light, "builder prune -f") {
		t.Errorf("軽の build cache prune が無い: %v", light)
	}

	heavy := flatten(PruneCommands(Heavy, nil))
	if !contains(heavy, "image prune -a -f") {
		t.Errorf("重で -a を使っていない: %v", heavy)
	}
	if !contains(heavy, "builder prune -a -f") {
		t.Errorf("重の build cache prune が -a でない: %v", heavy)
	}
}

// **--builder を付けないとカレントビルダーしか掃除しない。** default と
// docker-container ドライバは別のキャッシュを持つ（実測 11.2GB と 6.8GB）
func TestPruneCommandsCoverAllBuilders(t *testing.T) {
	got := flatten(PruneCommands(Light, []string{"default", "mybuilder"}))
	if !contains(got, "builder prune -f --builder default") {
		t.Errorf("default が無い: %v", got)
	}
	if !contains(got, "builder prune -f --builder mybuilder") {
		t.Errorf("mybuilder が無い: %v", got)
	}
	// **列挙できなかったときは --builder を付けない**（カレントだけを扱う）
	none := flatten(PruneCommands(Light, nil))
	for _, c := range none {
		if strings.Contains(c, "--builder") {
			t.Errorf("ビルダー不明なのに --builder を付けた: %q", c)
		}
	}
}

// **--filter until= は使わない。** 実測でどちらのドライバでも無視され、
// 7日以上前のレコードが残っていても一切回収されなかった
func TestPruneCommandsDoNotUseUntilFilter(t *testing.T) {
	for _, mode := range []Mode{Light, Heavy} {
		for _, c := range flatten(PruneCommands(mode, []string{"default"})) {
			if strings.Contains(c, "until=") {
				t.Errorf("until フィルタを使っている: %q", c)
			}
		}
	}
}

func TestRunContinuesAfterFailureAndSumsReclaimed(t *testing.T) {
	f := execx.NewFake()
	f.On("docker", execx.Result{ExitCode: 1, Stderr: "buildx not available"}) // buildx ls
	f.On("docker", execx.Result{Stdout: "Total reclaimed space: 1.5GB\n"})    // container prune
	f.On("docker", execx.Result{ExitCode: 1, Stderr: "boom"})                 // image prune（失敗）
	f.On("docker", execx.Result{Stdout: "Total reclaimed space: 500MB\n"})    // volume prune
	f.On("docker", execx.Result{Stdout: "Total:\t2GB\n"})                     // builder prune

	var out, errOut bytes.Buffer
	code := Run(context.Background(), f, Light, IO{Stdout: &out, Stderr: &errOut})

	if code != 1 {
		t.Errorf("失敗があるのに exit = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "1 件のコマンドが失敗しました") {
		t.Errorf("失敗件数を出していない: %q", errOut.String())
	}
	// **失敗しても残りを続行する**（volume と builder が走っている）
	if !strings.Contains(out.String(), "volume prune") || !strings.Contains(out.String(), "builder prune") {
		t.Errorf("後続を続行していない: %q", out.String())
	}
	// 回収量は「Total reclaimed space:」と buildkit の「Total:」の両方を拾う
	if !strings.Contains(out.String(), "回収: 4GB") {
		t.Errorf("回収量の合算が違う: %q", out.String())
	}
}

// --- プレビュー ---

func TestPreviewLightDoesNotEstimateBuildCacheSize(t *testing.T) {
	// **軽モードで build cache のサイズを出さない。** buildx du の Size は
	// 共有レイヤを含むうえ、軽モードはそのうち未使用ぶんだけを消すので、
	// 合算すると桁が変わる（246件/5.4GB と出して実際の回収が 0B になった）
	cfg := testConfig(t)
	s := &Stats{DF: []DFEntry{
		{Type: "Containers", Reclaimable: "1GB"},
		{Type: "Local Volumes", Reclaimable: "2GB"},
	}}

	f := execx.NewFake()
	f.On("docker", execx.Result{Stdout: "a\nb\nc\n"}) // ps -a -q（停止3件）
	f.On("docker", execx.Result{Stdout: "x\ny\n"})    // images dangling（2件）
	f.On("docker", execx.Result{Stdout: strings.Repeat("0", 64) + "\nnamed-vol\n"})
	f.On("docker", execx.Result{ExitCode: 1}) // buildx ls（列挙できない）
	f.On("docker", execx.Result{Stdout: "{\"Reclaimable\":true,\"Size\":\"5.4GB\"}\n"})

	var out bytes.Buffer
	Preview(context.Background(), f, cfg, s, Light, IO{Stdout: &out}, func(string) bool { return true })
	got := out.String()

	if !strings.Contains(got, "うち未使用ぶんのみ削除") {
		t.Errorf("軽の注記が無い: %q", got)
	}
	if strings.Contains(got, "5.4GB") {
		t.Errorf("軽モードで build cache のサイズを出している: %q", got)
	}
	// **匿名 volume（64桁 hex）だけを数える**
	if !strings.Contains(got, "※ named volume は対象外") {
		t.Errorf("named volume の注記が無い: %q", got)
	}
	// 回収見込みは Containers + Local Volumes のみ
	if !strings.Contains(got, "回収見込み 最大 約 3GB") {
		t.Errorf("回収見込みが違う: %q", got)
	}
}

func TestPreviewHeavyIncludesImagesAndBuildCache(t *testing.T) {
	cfg := testConfig(t)
	s := &Stats{DF: []DFEntry{
		{Type: "Containers", Reclaimable: "1GB"},
		{Type: "Images", TotalCount: "20", Active: "5", Reclaimable: "10GB"},
		{Type: "Local Volumes", Reclaimable: "2GB"},
	}}

	f := execx.NewFake()
	f.On("docker", execx.Result{Stdout: "a\n"})
	f.On("docker", execx.Result{Stdout: ""}) // volume ls
	f.On("docker", execx.Result{ExitCode: 1})
	f.On("docker", execx.Result{Stdout: "{\"Reclaimable\":true,\"Size\":\"3GB\"}\n"})

	var out bytes.Buffer
	Preview(context.Background(), f, cfg, s, Heavy, IO{Stdout: &out}, func(string) bool { return true })
	got := out.String()

	// 未使用 image の件数は TotalCount - Active
	if !strings.Contains(got, "未使用 image") || !strings.Contains(got, "15 件") {
		t.Errorf("未使用 image の件数が違う: %q", got)
	}
	if !strings.Contains(got, "回収見込み 最大 約 16GB") {
		t.Errorf("回収見込みが違う: %q", got)
	}
	if !strings.Contains(got, "共有レイヤを含むため実際はこれより少ない") {
		t.Errorf("重の注記が無い: %q", got)
	}
}

func TestPreviewShowsCopyableStopCommandsPerKind(t *testing.T) {
	// **種別で分けるのは停止の可逆性がまるで違うため。**
	cfg := testConfig(t)
	cfg.UptimeThresholdH = 12
	s := &Stats{Running: []Container{
		{Name: "orph", UptimeSeconds: 13 * 3600, ComposeProject: "gone-proj", ComposeDir: "/gone"},
		{Name: "comp", UptimeSeconds: 14 * 3600, ComposeProject: "live-proj", ComposeDir: "/live"},
		{Name: "solo", UptimeSeconds: 15 * 3600, AutoRemove: true},
	}}
	exists := func(p string) bool { return p == "/live" }

	f := execx.NewFake()
	for i := 0; i < 6; i++ {
		f.On("docker", execx.Result{})
	}

	var out bytes.Buffer
	Preview(context.Background(), f, cfg, s, Light, IO{Stdout: &out}, exists)
	got := out.String()

	for _, want := range []string{
		"[orphan]",
		"working_dir なし: /gone",
		"docker compose -p gone-proj down",
		"docker compose -p live-proj down",
		"# standalone（※--rm のコンテナは停止で削除されます）",
		"docker container stop solo",
		// **最終行に独立して出す**（停止しただけでは通知が古いまま）
		"dclean --refresh",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("出力に %q が無い:\n%s", want, got)
		}
	}
	// --rm の警告は行にも出す
	if !strings.Contains(got, "※--rm: 停止で削除されます") {
		t.Errorf("--rm の警告が無い: %q", got)
	}
}

func TestPreviewNotesExcludedContainers(t *testing.T) {
	// **出さないと docker ps と件数が合わず「表示に不足がある」ように見える。**
	cfg := testConfig(t)
	cfg.UptimeThresholdH = 12
	cfg.IgnorePatterns = []string{"buildx_buildkit_*"}
	s := &Stats{Running: []Container{
		{Name: "buildx_buildkit_default0", Image: "moby/buildkit", UptimeSeconds: 100 * 3600},
	}}

	f := execx.NewFake()
	for i := 0; i < 6; i++ {
		f.On("docker", execx.Result{})
	}

	var out bytes.Buffer
	Preview(context.Background(), f, cfg, s, Light, IO{Stdout: &out}, func(string) bool { return true })
	got := out.String()

	if !strings.Contains(got, "（除外 1 件") {
		t.Errorf("除外件数を出していない: %q", got)
	}
	if !strings.Contains(got, "閾値を超えて稼働しているコンテナはありません") {
		t.Errorf("除外後 0 件の表示が無い: %q", got)
	}
}

// --- ヘルパー ---

const dfJSONL = `{"Type":"Images","TotalCount":"20","Active":"5","Size":"12GB","Reclaimable":"10GB (83%)"}
{"Type":"Containers","TotalCount":"3","Active":"1","Size":"1GB","Reclaimable":"900MB"}
{"Type":"Local Volumes","TotalCount":"5","Active":"2","Size":"2GB","Reclaimable":"1.5GB"}
{"Type":"Build Cache","TotalCount":"100","Active":"0","Size":"5GB","Reclaimable":"5GB"}
`

const inspectLine = "/myapp|nginx:latest|2023-11-14T00:00:00Z|proj|/work/proj|true\n"

func itoa(n int64) string {
	return strings.TrimSpace(strings.Replace(strings.Replace(
		string([]byte(formatInt(n))), "\n", "", -1), " ", "", -1))
}

func formatInt(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	if neg {
		return "-" + string(b)
	}
	return string(b)
}

func flatten(cmds [][]string) []string {
	var out []string
	for _, c := range cmds {
		out = append(out, strings.Join(c, " "))
	}
	return out
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}
