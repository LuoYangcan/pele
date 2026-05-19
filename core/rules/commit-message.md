# Commit Message 风格

- Conventional commits：`type(scope): description`
- 单行、简短，只写"做了什么"。原因 / 背景 / 动机留给 PR 描述
- 多数情况用 `git commit -m "..."` 一行搞定；只在加 Co-Authored-By trailer 时用 HEREDOC

## Co-Authored-By trailer 按仓库区分

每次 commit 前看 `git remote get-url origin` 的 owner：

- **个人 / 公开作品仓库**（你自己的 GitHub username 下、开源 harness、个人 side project）→ **加 trailer**
- **公司 / 团队协作仓库**（公司 organization 下、闭源项目、多人协作私仓）→ **不加**
- **不确定 / 没有 origin / fork 关系不清** → **不加**（保守默认）

## 写法

加 trailer：

```bash
git commit -m "$(cat <<'EOF'
feat(scope): description

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

trailer 前必须有一空行（Git trailer 标准）。

不加 trailer：

```bash
git commit -m "feat(scope): description"
```

## 已有 commit 不补

forward-looking 生效。已 push 的 commit **不**做 history rewrite 补 trailer。
