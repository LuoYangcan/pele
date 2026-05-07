# Commit Message 风格

- Conventional commits：`type(scope): description`
- **单行、简短**，只写"做了什么"
- 原因、背景、动机留给 PR 描述或代码注释，不进 commit message
- 多数情况用 `git commit -m "..."` 一行搞定；只在要加 Co-Authored-By trailer 时才用 HEREDOC

## Co-Authored-By trailer 按仓库区分

是否在 commit 末尾加 `Co-Authored-By: Claude ...` trailer，按目标仓库的属性决定。每次 commit 前先看 `git remote get-url origin` 的 owner：

- **个人 / 公开作品仓库**（你自己的 GitHub username 下的仓库、开源 harness、个人 side project）→ **加 trailer**：
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
  这样 Claude 会进 GitHub Contributors，作为公开作品的协作记录。
- **公司 / 团队协作仓库**（公司 organization 下的仓库、闭源项目、多人协作私仓）→ **不加**，message 保持单行干净。同事 review 时 commit log 不被 LLM 协作信号污染。
- **不确定 / 没有 origin / fork 关系不清** → **不加**（保守默认）。

哪些 owner 算"个人 / 公开"由你自己列清楚 —— 通常是你的 GitHub username。把这个判断条件写进**你的本地版 rule**（`~/.claude/rules/commit-message.md`，install.sh 后会从 pele symlink 过来；如要 per-user 定制，把它替换成普通文件）。

## 写法

加 trailer 时：

```bash
git commit -m "$(cat <<'EOF'
feat(scope): description

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

trailer 前必须有一空行（Git trailer 标准）。

不加 trailer 时：

```bash
git commit -m "feat(scope): description"
```

## 已有 commit 不补

本 rule forward-looking 生效。已经 push 出去的 commit **不**为了补 trailer 做 history rewrite —— 风险大、push 远端会冲突、其他人 pull 后产生分叉。Claude 进 Contributors 是 nice-to-have，不值得为它折腾历史。
