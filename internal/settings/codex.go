package settings

import (
	"fmt"
	"os"
	"reflect"
	"sort"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

// CodexConfig はCodexの実設定と、リポジトリで共有するテンプレートの場所。
type CodexConfig struct {
	Live     string
	Template string
}

// CodexStatus は機械固有・実行時生成のtableを除外して設定を意味的に比較する。
// 値は機密情報を含み得るため、差分にはキー名だけを出す。
func CodexStatus(cfg CodexConfig, w IO) Outcome {
	live, err := readCodexConfig(cfg.Live)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: Codex実設定を読めない: %s: %v\n", cfg.Live, err)
		return Failed
	}
	template, err := readCodexConfig(cfg.Template)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: Codexテンプレートを読めない: %s: %v\n", cfg.Template, err)
		return Failed
	}

	maskCodexLocal(live)
	maskCodexLocal(template)
	diffs := codexKeyDiffs(live, template)
	if len(diffs) == 0 {
		fmt.Fprintln(w.out(), "一致: Codex実設定の共有項目はテンプレートと一致しています")
		return Unchanged
	}

	fmt.Fprintln(w.out(), "差分あり（値は非表示）:")
	for _, diff := range diffs {
		fmt.Fprintf(w.out(), "  %s\n", diff)
	}
	return WouldWrite
}

func readCodexConfig(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg map[string]any
	if err := toml.Unmarshal(b, &cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func maskCodexLocal(cfg map[string]any) {
	delete(cfg, "projects")
	delete(cfg, "notice")
	deleteNested(cfg, "tui", "model_availability_nux")
	deleteNested(cfg, "hooks", "state")
}

func deleteNested(cfg map[string]any, table, key string) {
	v, ok := cfg[table].(map[string]any)
	if !ok {
		return
	}
	delete(v, key)
	if len(v) == 0 {
		delete(cfg, table)
	}
}

func codexKeyDiffs(live, template map[string]any) []string {
	liveFlat := flattenCodex(live, "", nil)
	templateFlat := flattenCodex(template, "", nil)
	keys := make(map[string]struct{}, len(liveFlat)+len(templateFlat))
	for key := range liveFlat {
		keys[key] = struct{}{}
	}
	for key := range templateFlat {
		keys[key] = struct{}{}
	}

	var diffs []string
	for key := range keys {
		lv, lok := liveFlat[key]
		tv, tok := templateFlat[key]
		switch {
		case !lok:
			diffs = append(diffs, "実設定にない: "+key)
		case !tok:
			diffs = append(diffs, "テンプレートにない: "+key)
		case !reflect.DeepEqual(lv, tv):
			diffs = append(diffs, "値が異なる: "+key)
		}
	}
	sort.Strings(diffs)
	return diffs
}

func flattenCodex(v map[string]any, prefix string, out map[string]any) map[string]any {
	if out == nil {
		out = make(map[string]any)
	}
	for key, value := range v {
		path := strings.TrimPrefix(prefix+"."+key, ".")
		if nested, ok := value.(map[string]any); ok {
			flattenCodex(nested, path, out)
			continue
		}
		out[path] = value
	}
	return out
}
