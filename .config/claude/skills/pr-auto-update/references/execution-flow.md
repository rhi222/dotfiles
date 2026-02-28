# 実行フロー

```bash
#!/bin/bash

# 1. PR の検出・取得
detect_pr() {
  if [ -n "$PR_NUMBER" ]; then
    echo $PR_NUMBER
  else
    gh pr list --head $(git branch --show-current) --json number --jq '.[0].number'
  fi
}

# 2. 変更内容の分析
analyze_changes() {
  local pr_number=$1
  gh pr diff $pr_number --name-only
  gh pr diff $pr_number | head -1000
}

# 3. 説明文の生成
generate_description() {
  local pr_number=$1
  local current_body=$(gh pr view $pr_number --json body --jq -r .body)

  if [ -n "$current_body" ]; then
    echo "$current_body"
  else
    local template_file=".github/PULL_REQUEST_TEMPLATE.md"
    if [ -f "$template_file" ]; then
      generate_from_template "$(cat "$template_file")" "$changes"
    else
      generate_from_template "" "$changes"
    fi
  fi
}

# 4. ラベルの決定
determine_labels() {
  local changes=$1 file_list=$2 pr_number=$3

  # 利用可能なラベルを取得
  if [ -f ".github/labels.yml" ]; then
    grep "^- name:" .github/labels.yml | sed "s/^- name: '\?\([^']*\)'\?/\1/"
  else
    local repo_info=$(gh repo view --json owner,name)
    local owner=$(echo "$repo_info" | jq -r .owner.login)
    local repo=$(echo "$repo_info" | jq -r .name)
    gh api "repos/$owner/$repo/labels" --jq '.[].name'
  fi
  # 最大 3 個に制限
}

# 5. PR の更新
update_pr() {
  local pr_number=$1 description="$2" labels="$3"

  if [ "$DRY_RUN" = "true" ]; then
    echo "=== DRY RUN ==="
    echo "Description:" && echo "$description"
    echo "Labels: $labels"
  else
    local repo_info=$(gh repo view --json owner,name)
    local owner=$(echo "$repo_info" | jq -r .owner.login)
    local repo=$(echo "$repo_info" | jq -r .name)

    gh api --method PATCH "/repos/$owner/$repo/pulls/$pr_number" \
      --field body="$description"

    if [ -n "$labels" ]; then
      gh pr edit $pr_number --add-label "$labels"
    fi
  fi
}
```
