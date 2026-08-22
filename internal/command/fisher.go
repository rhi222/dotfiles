package command

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

const fisherUpdateUsage = `使い方: dotctl fisher-update

  fish_plugins のremote commitを前回成功時と比較し、変更時だけfisher updateする。
`

var fullCommitRE = regexp.MustCompile(`^[0-9a-fA-F]{40}$`)

func runFisherUpdate(ctx context.Context, args []string, env Env) int {
	if len(args) > 0 {
		if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
			fmt.Fprint(env.Stdout, fisherUpdateUsage)
			return 0
		}
		fmt.Fprint(env.Stderr, fisherUpdateUsage)
		return 2
	}
	if env.Runner == nil || env.FisherPluginFile == "" || env.FisherCacheFile == "" {
		fmt.Fprintln(env.Stderr, "fisher update: 設定が不足しています")
		return 1
	}

	state, count, cacheable, err := fisherRemoteState(ctx, env)
	if err != nil {
		fmt.Fprintf(env.Stderr, "fisher update: %v\n", err)
		return 1
	}
	if cacheable {
		if old, readErr := os.ReadFile(env.FisherCacheFile); readErr == nil && bytes.Equal(old, state) {
			fmt.Fprintf(env.Stdout, "fisher update: unchanged (%d plugins), skipping\n", count)
			return 0
		}
	}

	fmt.Fprintln(env.Stdout, "fisher update: changes detected, running full reconcile")
	res, runErr := env.Runner.Run(ctx, execx.Cmd{Name: "fish", Args: []string{"-c", "fisher update"}})
	fmt.Fprint(env.Stdout, res.Stdout)
	fmt.Fprint(env.Stderr, res.Stderr)
	if runErr != nil {
		fmt.Fprintf(env.Stderr, "fisher update: %v\n", runErr)
		return 1
	}
	if !res.OK() {
		return res.ExitCode
	}

	if !cacheable {
		if err := os.Remove(env.FisherCacheFile); err != nil && !errors.Is(err, os.ErrNotExist) {
			fmt.Fprintf(env.Stderr, "fisher update: 古いcacheを削除できない: %v\n", err)
			return 1
		}
		return 0
	}
	if err := writeFisherCache(env.FisherCacheFile, state); err != nil {
		fmt.Fprintf(env.Stderr, "fisher update: cacheを保存できない: %v\n", err)
		return 1
	}
	return 0
}

func fisherRemoteState(ctx context.Context, env Env) ([]byte, int, bool, error) {
	f, err := os.Open(env.FisherPluginFile)
	if err != nil {
		return nil, 0, false, fmt.Errorf("fish_pluginsを開けない: %w", err)
	}
	defer f.Close()

	var state bytes.Buffer
	state.WriteString("fisher-cache-v1\n")
	count := 0
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		plugin := strings.TrimSpace(strings.SplitN(scanner.Text(), "#", 2)[0])
		if plugin == "" {
			continue
		}
		sha, supported, err := resolveFisherPlugin(ctx, env.Runner, plugin)
		if err != nil {
			return nil, 0, false, err
		}
		if !supported {
			fmt.Fprintf(env.Stderr, "fisher update: cache対象外のplugin: %s\n", plugin)
			return nil, 0, false, nil
		}
		fmt.Fprintf(&state, "%s\t%s\n", plugin, sha)
		count++
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, false, err
	}
	return state.Bytes(), count, true, nil
}

func resolveFisherPlugin(ctx context.Context, runner execx.Runner, plugin string) (string, bool, error) {
	spec := strings.TrimPrefix(strings.TrimPrefix(plugin, "https://github.com/"), "github.com/")
	at := strings.LastIndex(spec, "@")
	repo, ref := spec, "HEAD"
	if at >= 0 {
		repo, ref = spec[:at], spec[at+1:]
	}
	repo = strings.TrimSuffix(repo, ".git")
	parts := strings.Split(repo, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" || ref == "" {
		return "", false, nil
	}
	if fullCommitRE.MatchString(ref) {
		return strings.ToLower(ref), true, nil
	}

	args := []string{"ls-remote", "https://github.com/" + repo + ".git"}
	if ref == "HEAD" {
		args = append(args, "HEAD")
	} else {
		args = append(args, "refs/tags/"+ref+"^{}", "refs/tags/"+ref, "refs/heads/"+ref)
	}
	res, err := runner.Run(ctx, execx.Cmd{Name: "git", Args: args})
	if err != nil || !res.OK() {
		return "", true, fmt.Errorf("remoteを確認できない: %s", plugin)
	}
	refs := map[string]string{}
	for _, line := range strings.Split(res.Stdout, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 {
			refs[fields[1]] = fields[0]
		}
	}
	for _, name := range []string{"refs/tags/" + ref + "^{}", "refs/tags/" + ref, "refs/heads/" + ref, "HEAD"} {
		if sha := refs[name]; sha != "" {
			return sha, true, nil
		}
	}
	return "", true, fmt.Errorf("remote refが見つからない: %s", plugin)
}

func writeFisherCache(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".fisher-update-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}
