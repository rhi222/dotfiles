// Package buildinfo はビルド時に -ldflags で埋め込む情報を持つ。
//
// **ここが version skew 検知の土台。** git pull 後に再ビルドしなければ、
// cron と hook は古いバイナリを黙って実行し続ける（daily-update.sh が
// 古い installs/<tool>/ の gh を掴んだ事故と同型）。バイナリに「どの
// コミットから作られたか」と「どのリポジトリから作られたか」を持たせて、
// 実行時にGoのbuild入力が変わったか調べられるようにする。
package buildinfo

// ビルド時に上書きする。値が空のままなら skew 検知を行わない
// （go run や -ldflags なしのビルドで毎回警告を出さないため）。
var (
	// Commit はビルド元のコミットハッシュ。
	Commit = ""
	// Repo はビルド元のリポジトリのパス。
	Repo = ""
	// SourceHash はGoのbuild入力から計算したfingerprint。
	SourceHash = ""
)
