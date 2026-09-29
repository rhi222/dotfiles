package command

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

const yaziUpdateUsage = `使い方: dotctl yazi-update

  package.tomlのrevとremote HEADを比較し、変更時だけya pkg upgradeを実行する。
  前回deploy後にpackage.tomlだけが変わっていれば、先にya pkg install --discardで揃える。
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

	if code := syncYaziPulledPackages(ctx, env); code != 0 {
		return code
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
	return runYaziPkg(ctx, env, "upgrade")
}

// syncYaziPulledPackages は他端末のupgradeをpullした後の中身を宣言に揃える。
//
// package.tomlはrepoで共有するが、中身の plugins/ はgitignoreしている。pullで
// package.tomlだけが進むと、yaはhashの合わない古い中身を「手元の編集」と見なして
// upgradeを拒否する。**--discardは本物の編集も捨てる**ので、この端末で最後に
// deployした中身から変わっていないと確かめられたときだけ使う。
func syncYaziPulledPackages(ctx context.Context, env Env) int {
	if env.YaziStateFile == "" {
		return 0
	}
	saved, err := os.ReadFile(env.YaziStateFile)
	if err != nil {
		// 記録が無ければ中身の出自が分からないので触らない
		return 0
	}
	savedToml, savedBody, _ := strings.Cut(string(saved), "\n")
	toml, body, err := yaziFingerprints(env.YaziPackageFile)
	if err != nil {
		fmt.Fprintf(env.Stderr, "yazi update: 中身を確認できない: %v\n", err)
		return 1
	}
	if toml == savedToml {
		return 0
	}
	if body != strings.TrimSpace(savedBody) {
		fmt.Fprintln(env.Stderr, "yazi update: 前回deploy後にpluginの中身が変更されているため、package.tomlに揃えない")
		return 0
	}
	fmt.Fprintln(env.Stdout, "yazi update: package.toml changed since last deploy, syncing packages")
	return runYaziPkg(ctx, env, "install", "--discard")
}

func runYaziPkg(ctx context.Context, env Env, args ...string) int {
	res, err := env.Runner.Run(ctx, execx.Cmd{Name: env.YaziBin, Args: append([]string{"pkg"}, args...)})
	fmt.Fprint(env.Stdout, res.Stdout)
	fmt.Fprint(env.Stderr, res.Stderr)
	if err != nil {
		fmt.Fprintf(env.Stderr, "yazi update: %v\n", err)
		return 1
	}
	if res.ExitCode != 0 {
		return res.ExitCode
	}
	return recordYaziState(env)
}

func recordYaziState(env Env) int {
	if env.YaziStateFile == "" {
		return 0
	}
	toml, body, err := yaziFingerprints(env.YaziPackageFile)
	if err == nil {
		err = writeFileAtomic(env.YaziStateFile, []byte(toml+"\n"+body+"\n"))
	}
	if err != nil {
		fmt.Fprintf(env.Stderr, "yazi update: deploy状態を記録できない: %v\n", err)
		return 1
	}
	return 0
}

// yaziFingerprints はpackage.tomlと、その隣の plugins/・flavors/ の中身のhashを返す。
func yaziFingerprints(packageFile string) (string, string, error) {
	toml, err := os.ReadFile(packageFile)
	if err != nil {
		return "", "", err
	}
	tomlSum := sha256.Sum256(toml)

	h := sha256.New()
	dir := filepath.Dir(packageFile)
	for _, sub := range []string{"plugins", "flavors"} {
		err := filepath.WalkDir(filepath.Join(dir, sub), func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				if os.IsNotExist(err) {
					return nil
				}
				return err
			}
			if d.IsDir() {
				return nil
			}
			b, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(dir, path)
			fmt.Fprintf(h, "%s\x00%d\x00", rel, len(b))
			h.Write(b)
			return nil
		})
		if err != nil {
			return "", "", err
		}
	}
	return hex.EncodeToString(tomlSum[:]), hex.EncodeToString(h.Sum(nil)), nil
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
