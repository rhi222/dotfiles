package settings

import (
	"bufio"
	"encoding/json"
	"os"
	"regexp"
	"strings"
)

// maskedKeys はマスク対象のトップレベルキー。
//
// **このリポジトリは public なので、社内プラグイン名とその git URL を入れない。**
// 値は見ずキー名だけで判定する（キーが "<plugin>@<marketplace>" 形式で、
// marketplace 名に社名が入るため）。
var maskedKeys = []string{"enabledPlugins", "extraKnownMarketplaces"}

// SecretRegex は機密語辞書から判定用の正規表現を組む。
//
// **辞書が無ければ空を返す（＝マスクしない）。** 新環境で bootstrap 前に
// 同期が壊れるのを避けるため、辞書不在は許容する。
func SecretRegex(dictPath string) (*regexp.Regexp, error) {
	f, err := os.Open(dictPath)
	if err != nil {
		return nil, nil
	}
	defer func() { _ = f.Close() }()

	var pats []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		pats = append(pats, line)
	}
	if len(pats) == 0 {
		return nil, nil
	}
	re, err := regexp.Compile(strings.Join(pats, "|"))
	if err != nil {
		return nil, err
	}
	return re, nil
}

// Mask は JSON から機密エントリを落とす。re が nil なら正規化だけ行う。
func Mask(content string, re *regexp.Regexp) (string, error) {
	if re == nil {
		return Canonical([]byte(content))
	}
	v, err := decodeObject(content)
	if err != nil {
		return "", err
	}
	for _, k := range maskedKeys {
		sub, ok := v[k].(map[string]any)
		if !ok {
			continue
		}
		kept := map[string]any{}
		for key, val := range sub {
			if !re.MatchString(key) {
				kept[key] = val
			}
		}
		v[k] = kept
	}
	return encodeObject(v)
}

// Merge はリポジトリ版に実ファイル側の機密エントリを戻す。
//
// **push でリポジトリ版を書き出すとき、実ファイル側にしかない社内設定を
// 消さないために使う。** これが無いと push のたびに社内プラグインの有効化が消える。
func Merge(repoContent, liveContent string, re *regexp.Regexp) (string, error) {
	if re == nil {
		return Canonical([]byte(repoContent))
	}
	repo, err := decodeObject(repoContent)
	if err != nil {
		return "", err
	}
	live, err := decodeObject(liveContent)
	if err != nil {
		return "", err
	}

	for _, k := range maskedKeys {
		liveSub, ok := live[k].(map[string]any)
		if !ok {
			continue
		}
		secrets := map[string]any{}
		for key, val := range liveSub {
			if re.MatchString(key) {
				secrets[key] = val
			}
		}
		if len(secrets) == 0 {
			continue
		}
		merged := map[string]any{}
		if repoSub, ok := repo[k].(map[string]any); ok {
			for key, val := range repoSub {
				merged[key] = val
			}
		}
		for key, val := range secrets {
			merged[key] = val
		}
		repo[k] = merged
	}
	return encodeObject(repo)
}

func decodeObject(content string) (map[string]any, error) {
	dec := json.NewDecoder(strings.NewReader(content))
	dec.UseNumber()
	var v map[string]any
	if err := dec.Decode(&v); err != nil {
		return nil, err
	}
	return v, nil
}

func encodeObject(v map[string]any) (string, error) {
	// Canonical に通すためいったんバイト列へ戻す。**ここで
	// encoding/json の既定エンコードを表に出さない**（HTML エスケープが混ざる）。
	b, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return Canonical(b)
}
