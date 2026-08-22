// settingsのcanonical化はJSONの意味と数値を保ち、壊れたJSONやJSONCを反対側へ伝播しない。
package settings

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCanonicalSortsKeysAndIndents(t *testing.T) {
	got, err := Canonical([]byte(`{"b":1,"a":{"z":true,"y":null}}`))
	if err != nil {
		t.Fatal(err)
	}
	want := "{\n  \"a\": {\n    \"y\": null,\n    \"z\": true\n  },\n  \"b\": 1\n}\n"
	if got != want {
		t.Errorf("got  %q\nwant %q", got, want)
	}
}

func TestCanonicalDoesNotHTMLEscape(t *testing.T) {
	// **encoding/json の既定は < > & をエスケープする。** jq はしないので、
	// 既定のままだと同期のたびに差分が出続ける
	got, err := Canonical([]byte(`{"v":"a<b>c&d"}`))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, `"a<b>c&d"`) {
		t.Errorf("HTML エスケープしている: %q", got)
	}
}

func TestCanonicalPreservesNumberLiterals(t *testing.T) {
	for _, in := range []string{"1", "1.0", "1.50", "-0", "0.30000000000000004", "12345678901234567890"} {
		got, err := Canonical([]byte(`{"v":` + in + `}`))
		if err != nil {
			t.Fatalf("%s: %v", in, err)
		}
		if !strings.Contains(got, `"v": `+in) {
			t.Errorf("%s のリテラルが変わった: %q", in, got)
		}
	}
}

func TestCanonicalKeepsEmptyContainers(t *testing.T) {
	got, err := Canonical([]byte(`{"o":{},"a":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\n  \"a\": [],\n  \"o\": {}\n}\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestCanonicalRejectsBrokenJSON(t *testing.T) {
	// **壊れた設定を相手側へ伝播させないための門番。**
	for _, in := range []string{`{`, `{"a":}`, ``, `{"a":1} trailing`, `// comment`} {
		if _, err := Canonical([]byte(in)); err == nil {
			t.Errorf("%q を通してしまった", in)
		}
	}
}

func TestCanonicalRejectsJSONC(t *testing.T) {
	// Windows Terminal の settings.json は JSONC を許容するので、コメントを
	// 書かれると同期が止まる。**止まるのが正しい**（壊れた内容を伝播させない）
	in := "{\n  // コメント\n  \"a\": 1\n}\n"
	if _, err := Canonical([]byte(in)); err == nil {
		t.Error("JSONC を通してしまった")
	}
}

// jq -S . との一致を実物で確認する。**「jq と同じ」が正規化の定義**なので、
// ここが緑でないと移植の前提が崩れる。
func TestCanonicalMatchesJq(t *testing.T) {
	if testing.Short() {
		t.Skip("jq を起動するので -short では飛ばす")
	}
	if _, err := exec.LookPath("jq"); err != nil {
		t.Skip("jq が無い")
	}

	cases := []string{
		`{"b":1,"a":2,"nested":{"z":[1,2,{"y":null}],"a":{}},"empty":[],"t":true,"f":false}`,
		`{"num_int":1,"num_float":1.0,"trailing":1.50,"neg":-12.5,"big":12345678901234567890}`,
		`{"html":"a<b>c&d","quote":"he said \"hi\"","tab":"a\tb","nl":"a\nb"}`,
		`{"日本語":"値","emoji":"⚡","escaped":"é"}`,
		`{}`,
		`{"a":{"b":{"c":{"d":1}}}}`,
		`{"slash":"a/b","backslash":"a\\b","ctrl":"a\\u0001b"}`,
		`{"arr":[{"b":1,"a":2},{"d":3,"c":4}]}`,
		// 実物に近い形（skillOverrides / enabledPlugins のような入れ子）
		`{"permissions":{"deny":["Read(~/.aws/**)"],"allow":[]},"statusLine":{"command":"x","padding":0}}`,
	}
	dir := t.TempDir()
	for i, in := range cases {
		path := filepath.Join(dir, "c.json")
		if err := os.WriteFile(path, []byte(in), 0o644); err != nil {
			t.Fatal(err)
		}
		out, err := exec.Command("jq", "-S", ".", path).Output()
		if err != nil {
			t.Fatalf("[%d] jq: %v", i, err)
		}
		got, err := Canonical([]byte(in))
		if err != nil {
			t.Fatalf("[%d] Canonical: %v", i, err)
		}
		if got != string(out) {
			t.Errorf("[%d] jq と違う\n got  %q\n want %q", i, got, string(out))
		}
	}
}

// 実リポジトリの設定ファイルでも jq と一致すること。
// **本番で使うのはこの形**なので、合成ケースだけでは足りない。
func TestCanonicalMatchesJqOnRealFiles(t *testing.T) {
	if testing.Short() {
		t.Skip("jq を起動するので -short では飛ばす")
	}
	if _, err := exec.LookPath("jq"); err != nil {
		t.Skip("jq が無い")
	}
	root := repoRoot(t)
	for _, rel := range []string{
		".config/claude/settings.json",
		".config/windows-terminal/settings.json",
		".config/ccstatusline/settings.json",
	} {
		path := filepath.Join(root, rel)
		b, err := os.ReadFile(path)
		if err != nil {
			t.Logf("skip %s: %v", rel, err)
			continue
		}
		out, err := exec.Command("jq", "-S", ".", path).Output()
		if err != nil {
			t.Fatalf("%s: jq: %v", rel, err)
		}
		got, err := Canonical(b)
		if err != nil {
			t.Fatalf("%s: %v", rel, err)
		}
		if got != string(out) {
			t.Errorf("%s で jq と違う", rel)
		}
	}
}

// 既知の差を明示しておく。**隠すと後で「なぜか差分が出る」になる。**
func TestCanonicalKnownDifferenceOnExponents(t *testing.T) {
	got, err := Canonical([]byte(`{"v":1e3}`))
	if err != nil {
		t.Fatal(err)
	}
	// jq は 1E+3 にするが、ここは入力のまま出す。設定ファイルに指数表記は
	// 現れないので実害が無く、jq の丸め規則を推測で再実装するほうが危険
	if !strings.Contains(got, "1e3") {
		t.Errorf("入力のリテラルを保っていない: %q", got)
	}
}

// repoRoot はテスト実行位置からリポジトリのルートを解く。
func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	// internal/settings から2階層上
	return filepath.Dir(filepath.Dir(wd))
}
