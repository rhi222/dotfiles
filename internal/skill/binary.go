package skill

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"

	"github.com/rhi222/dotfiles/internal/execx"
)

// binaryDesc は非テキストファイルの finding の説明。除外判定で照合する。
const binaryDesc = "非テキストファイル（レビューできない）"

// FileSHA256 はファイル内容の SHA-256 を16進で返す。
func FileSHA256(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

// AuditReviewed は Audit を走らせ、人が確認済みの非テキストファイルを除く。
//
// **除くのは記録した digest と今の内容が一致するときだけ。** 差し替わった
// バイナリは HIGH のまま残る。
func AuditReviewed(ctx context.Context, r execx.Runner, dir string, reviewed map[string]string) (AuditResult, error) {
	res, err := Audit(ctx, r, dir)
	if err != nil {
		return res, err
	}
	filtered := AuditResult{}
	for _, f := range res.Findings {
		if f.Level == HIGH && f.Desc == binaryDesc {
			want, ok := reviewed[f.Path]
			got, herr := FileSHA256(filepath.Join(dir, f.Path))
			if ok && herr == nil && got == want {
				continue
			}
		}
		filtered.Findings = append(filtered.Findings, f)
		switch f.Level {
		case HIGH:
			filtered.High++
		case MED:
			filtered.Med++
		default:
			filtered.Low++
		}
	}
	return filtered, nil
}
