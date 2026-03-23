#!/usr/bin/env bash
# セッションパターン分析用データ収集スクリプト
# 使い方: DAYS=7 source collect-session-patterns.sh
#
# 環境変数:
#   DAYS - 分析対象日数（デフォルト7, 最大30）

DAYS="${DAYS:-7}"
if [ "$DAYS" -gt 30 ]; then
    echo "⚠️ 最大30日です。30日に制限します。"
    DAYS=30
fi

CUTOFF_MS=$(( ($(date +%s) - DAYS * 86400) * 1000 ))
START_DATE=$(date -d "$DAYS days ago" +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)

echo "🔍 セッションパターン分析データ収集"
echo "期間: $START_DATE 〜 $END_DATE（${DAYS}日間）"
echo "================================"
echo ""

# Phase A: history.jsonl からプロンプト履歴を抽出・集計
HISTORY_FILE="$HOME/.claude/history.jsonl"

if [ ! -f "$HISTORY_FILE" ]; then
    echo "⚠️ history.jsonl が見つかりません: $HISTORY_FILE"
    echo "セッション履歴データなし"
else
    python3 << PYEOF
import json, os
from collections import Counter

cutoff_ms = $CUTOFF_MS
history_file = "$HISTORY_FILE"

entries = []
with open(history_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get('timestamp', 0) >= cutoff_ms:
            entries.append(e)

if not entries:
    print("⚠️ 期間内のプロンプト履歴がありません")
else:
    # スキルコマンド vs 自然言語プロンプトを分類
    skill_cmds = []
    natural = []
    noise = {'/clear', 'exit', 'yes', 'no', 'y', 'n', ''}

    for e in entries:
        display = str(e.get('display', '')).strip()
        if display.lower() in noise:
            continue
        if display.startswith('/'):
            skill_cmds.append(e)
        else:
            natural.append(e)

    print(f"📊 期間内統計")
    print(f"  総プロンプト数: {len(entries)}")
    print(f"  スキルコマンド: {len(skill_cmds)}")
    print(f"  自然言語プロンプト: {len(natural)}")
    print()

    # スキル利用頻度
    if skill_cmds:
        skill_freq = Counter()
        for e in skill_cmds:
            cmd = str(e.get('display', '')).split()[0]
            skill_freq[cmd] += 1
        print("=== スキル利用頻度 ===")
        for cmd, count in skill_freq.most_common(15):
            print(f"  {cmd}: {count}回")
        print()

    # プロジェクト別プロンプト
    if natural:
        by_project = {}
        for e in natural:
            proj = str(e.get('project', 'unknown')).split('/')[-1]
            if not proj:
                proj = 'unknown'
            by_project.setdefault(proj, []).append(str(e.get('display', ''))[:100])

        print("=== プロジェクト別・自然言語プロンプト ===")
        # プロンプト数の多い順に表示
        for proj, prompts in sorted(by_project.items(), key=lambda x: -len(x[1])):
            print(f"[{proj}] ({len(prompts)}件)")
            for p in prompts[:5]:
                print(f"  - {p}")
            if len(prompts) > 5:
                print(f"  ... 他{len(prompts)-5}件")
            print()
PYEOF
fi

echo ""

# Phase B: sessions-index.json からセッションサマリーを収集
PROJECTS_DIR="$HOME/.claude/projects"

if [ ! -d "$PROJECTS_DIR" ]; then
    echo "⚠️ projects ディレクトリが見つかりません"
else
    python3 << PYEOF
import json, os
from datetime import datetime, timezone, timedelta

cutoff = datetime.now(timezone.utc) - timedelta(days=$DAYS)
projects_dir = "$PROJECTS_DIR"

summaries = []
for proj_name in os.listdir(projects_dir):
    idx = os.path.join(projects_dir, proj_name, 'sessions-index.json')
    if not os.path.exists(idx):
        continue
    try:
        with open(idx) as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue
    for e in data.get('entries', []):
        modified_str = e.get('modified', '')
        if not modified_str:
            continue
        try:
            modified = datetime.fromisoformat(modified_str.replace('Z', '+00:00'))
        except ValueError:
            continue
        if modified >= cutoff:
            proj_path = e.get('projectPath', '')
            proj_short = proj_path.split('/')[-1] if proj_path else proj_name
            summaries.append({
                'date': modified.strftime('%Y-%m-%d'),
                'project': proj_short,
                'summary': e.get('summary', ''),
                'firstPrompt': str(e.get('firstPrompt', ''))[:80],
                'messageCount': e.get('messageCount', 0),
            })

summaries.sort(key=lambda x: x['date'], reverse=True)

print(f"=== 最近のセッションサマリー ({len(summaries)}件) ===")
for s in summaries:
    print(f"  [{s['date']}] [{s['project']}] {s['summary']}")
    print(f"    初回: {s['firstPrompt']}")
    print(f"    メッセージ数: {s['messageCount']}")
print()
PYEOF
fi

echo "✅ セッションパターンデータ収集完了"
