package settings

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestSecretRegexReadsDictionary(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "secret-patterns.txt")
	body := "# コメントは無視する\n\nexample-corp\nexample\\.internal\n\n# 末尾コメント\n"
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	re, err := SecretRegex(p)
	if err != nil {
		t.Fatal(err)
	}
	if re == nil {
		t.Fatal("辞書があるのに nil を返した")
	}
	if !re.MatchString("plugin@example-corp") {
		t.Error("辞書の語に一致しない")
	}
	if re.MatchString("plugin@anthropics") {
		t.Error("辞書に無い語に一致してしまう")
	}
}

func TestSecretRegexIsNilWhenDictionaryMissing(t *testing.T) {
	// **辞書が無ければマスクしない。** 新環境で bootstrap 前に同期が
	// 壊れるのを避けるため、辞書不在は許容する
	re, err := SecretRegex(filepath.Join(t.TempDir(), "nope.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if re != nil {
		t.Error("辞書が無いのに正規表現を返した")
	}
}

func TestSecretRegexIsNilWhenDictionaryHasOnlyComments(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "d.txt")
	if err := os.WriteFile(p, []byte("# only comments\n\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	re, err := SecretRegex(p)
	if err != nil {
		t.Fatal(err)
	}
	if re != nil {
		t.Error("空の辞書で正規表現を返した（全一致の空パターンは危険）")
	}
}

const withSecrets = `{
  "enabledPlugins": {
    "public-plugin@anthropics": true,
    "inner-plugin@example-corp": true
  },
  "extraKnownMarketplaces": {
    "anthropics": {"source": {"source": "github"}},
    "example-corp": {"source": {"source": "git", "url": "https://git.example-corp/x"}}
  },
  "theme": "dark"
}`

func TestMaskDropsSecretKeysOnly(t *testing.T) {
	re := regexp.MustCompile("example-corp")
	got, err := Mask(withSecrets, re)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "example-corp") {
		t.Errorf("機密キーが残っている:\n%s", got)
	}
	// **公開分は残す。** 全部落とすと同期の意味が無い
	if !strings.Contains(got, "public-plugin@anthropics") {
		t.Errorf("公開エントリを落としている:\n%s", got)
	}
	if !strings.Contains(got, `"anthropics"`) {
		t.Errorf("公開 marketplace を落としている:\n%s", got)
	}
	// マスク対象外のキーは触らない
	if !strings.Contains(got, `"theme": "dark"`) {
		t.Errorf("無関係なキーを触っている:\n%s", got)
	}
}

func TestMaskKeepsKeyPresentEvenWhenEmptied(t *testing.T) {
	// キー自体は残す（消すと push 側で「元から無い」と区別できない）
	re := regexp.MustCompile("example-corp")
	got, err := Mask(`{"enabledPlugins":{"a@example-corp":true}}`, re)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, `"enabledPlugins": {}`) {
		t.Errorf("キーごと消している:\n%s", got)
	}
}

func TestMaskWithoutRegexJustNormalizes(t *testing.T) {
	got, err := Mask(`{"b":1,"a":2}`, nil)
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\n  \"a\": 2,\n  \"b\": 1\n}\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestMergeRestoresSecretsFromLive(t *testing.T) {
	// **push で社内設定を消さないための復元。** これが無いと push のたびに
	// 社内プラグインの有効化が消える
	re := regexp.MustCompile("example-corp")
	repo := `{"enabledPlugins":{"public-plugin@anthropics":true},"theme":"dark"}`
	got, err := Merge(repo, withSecrets, re)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "inner-plugin@example-corp") {
		t.Errorf("実ファイル側の機密を戻していない:\n%s", got)
	}
	if !strings.Contains(got, "public-plugin@anthropics") {
		t.Errorf("リポジトリ側の公開分を落としている:\n%s", got)
	}
	if !strings.Contains(got, `"url": "https://git.example-corp/x"`) {
		t.Errorf("marketplace の機密を戻していない:\n%s", got)
	}
}

func TestMergeDoesNotInventKeysWhenLiveHasNoSecrets(t *testing.T) {
	re := regexp.MustCompile("example-corp")
	repo := `{"theme":"dark"}`
	live := `{"enabledPlugins":{"public@anthropics":true}}`
	got, err := Merge(repo, live, re)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "enabledPlugins") {
		t.Errorf("機密が無いのにキーを作っている:\n%s", got)
	}
}

func TestMergeWithoutRegexJustNormalizesRepo(t *testing.T) {
	got, err := Merge(`{"b":1,"a":2}`, `{"enabledPlugins":{"x@y":true}}`, nil)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "enabledPlugins") {
		t.Errorf("辞書が無いのに実ファイル側を混ぜている:\n%s", got)
	}
}

// **マスクとマージは往復して安定すること。** ここが崩れると
// pull と push を繰り返すたびに差分が出て、同期が収束しない。
func TestMaskMergeRoundTripIsStable(t *testing.T) {
	re := regexp.MustCompile("example-corp")

	masked, err := Mask(withSecrets, re)
	if err != nil {
		t.Fatal(err)
	}
	merged, err := Merge(masked, withSecrets, re)
	if err != nil {
		t.Fatal(err)
	}
	// merged を再びマスクすると masked に戻る
	remasked, err := Mask(merged, re)
	if err != nil {
		t.Fatal(err)
	}
	if remasked != masked {
		t.Errorf("往復で安定しない\n masked   %q\n remasked %q", masked, remasked)
	}
}
