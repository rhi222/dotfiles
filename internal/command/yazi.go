package command

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

const yaziUpdateUsage = `使い方: dotctl yazi-update

  package.tomlのrevとremote HEADを比較し、変更時だけya pkg upgradeを実行する。
`

var (
	yaziUseRE = regexp.MustCompile(`^\s*use\s*=\s*"([^"]+)"`)
	yaziRevRE = regexp.MustCompile(`^\s*rev\s*=\s*"([^"]+)"`)
	yaziSHA   = regexp.MustCompile(`^[0-9a-fA-F]{7,40}$`)
)

type yaziPackageRef struct {
	repo   string
	rev    string
	pinned bool
}

func runYaziUpdate(ctx context.Context, args []string, env Env) int {
	if len(args) > 0 {
		if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
			fmt.Fprint(env.Stdout, yaziUpdateUsage)
			return 0
		}
		fmt.Fprint(env.Stderr, yaziUpdateUsage)
		return 2
	}
	if env.Runner == nil || env.YaziPackageFile == "" || env.YaziBin == "" {
		fmt.Fprintln(env.Stderr, "yazi update: 設定が不足しています")
		return 1
	}

	refs, err := readYaziPackageRefs(env.YaziPackageFile)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprintf(env.Stdout, "yazi update: no package.toml at %s, skipping\n", env.YaziPackageFile)
			return 0
		}
		fmt.Fprintf(env.Stderr, "yazi update: package.tomlを読めない: %v\n", err)
		return 1
	}

	remote := make(map[string]string)
	for _, ref := range refs {
		if ref.pinned {
			continue
		}
		sha, ok := remote[ref.repo]
		if !ok {
			sha, err = yaziRemoteHEAD(ctx, env.Runner, ref.repo)
			if err != nil {
				fmt.Fprintf(env.Stderr, "yazi update: %v\n", err)
				return 1
			}
			remote[ref.repo] = sha
		}
		if !strings.HasPrefix(strings.ToLower(sha), strings.ToLower(ref.rev)) {
			return runYaziUpgrade(ctx, env, len(refs))
		}
	}

	fmt.Fprintf(env.Stdout, "yazi update: unchanged (%d packages), skipping\n", len(refs))
	return 0
}

func runYaziUpgrade(ctx context.Context, env Env, count int) int {
	fmt.Fprintf(env.Stdout, "yazi update: changes detected (%d packages), running upgrade\n", count)
	res, err := env.Runner.Run(ctx, execx.Cmd{Name: env.YaziBin, Args: []string{"pkg", "upgrade"}})
	fmt.Fprint(env.Stdout, res.Stdout)
	fmt.Fprint(env.Stderr, res.Stderr)
	if err != nil {
		fmt.Fprintf(env.Stderr, "yazi update: %v\n", err)
		return 1
	}
	return res.ExitCode
}

func readYaziPackageRefs(path string) ([]yaziPackageRef, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var refs []yaziPackageRef
	active := false
	use := ""
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(strings.TrimSpace(line), "[[") {
			if active && use != "" {
				return nil, fmt.Errorf("%s: useに対応するrevが無い", use)
			}
			section := strings.TrimSpace(line)
			active = section == "[[plugin.deps]]" || section == "[[flavor.deps]]"
			use = ""
			continue
		}
		if !active {
			continue
		}
		if m := yaziUseRE.FindStringSubmatch(line); m != nil {
			if use != "" {
				return nil, fmt.Errorf("%s: useに対応するrevが無い", use)
			}
			use = m[1]
			continue
		}
		if m := yaziRevRE.FindStringSubmatch(line); m != nil && use != "" {
			ref, err := newYaziPackageRef(use, m[1])
			if err != nil {
				return nil, err
			}
			refs = append(refs, ref)
			use = ""
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if active && use != "" {
		return nil, fmt.Errorf("%s: useに対応するrevが無い", use)
	}
	return refs, nil
}

func newYaziPackageRef(use, rev string) (yaziPackageRef, error) {
	repo := strings.SplitN(use, ":", 2)[0]
	parts := strings.Split(repo, "/")
	pinned := strings.HasPrefix(rev, "=")
	rev = strings.TrimPrefix(rev, "=")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" || !yaziSHA.MatchString(rev) {
		return yaziPackageRef{}, fmt.Errorf("未対応のpackage指定: use=%q rev=%q", use, rev)
	}
	return yaziPackageRef{repo: repo, rev: rev, pinned: pinned}, nil
}

func yaziRemoteHEAD(ctx context.Context, runner execx.Runner, repo string) (string, error) {
	res, err := runner.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"ls-remote", "https://github.com/" + repo + ".git", "HEAD"},
	})
	if err != nil || !res.OK() {
		return "", fmt.Errorf("remoteを確認できない: %s", repo)
	}
	fields := strings.Fields(res.Stdout)
	if len(fields) < 2 || fields[1] != "HEAD" || !fullCommitRE.MatchString(fields[0]) {
		return "", fmt.Errorf("remote HEADが不正: %s", repo)
	}
	return fields[0], nil
}
