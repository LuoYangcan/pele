# Codex model policy

`core/config/model-policy.json` is the canonical role policy. `scripts/model-policy.py` uses only Python 3 standard library and resolves each field in this order: default policy, `${CODEX_HOME:-~/.codex}/model-policy.local.json`, `<repo>/.codex/model-policy.json`, then CLI `--model` or `--effort`. Overlay files may contain only known roles and partial `model`/`effort` entries; invalid JSON, names, empty models, and efforts fail explicitly.

```bash
python3 scripts/model-policy.py show implementer --repo /path/to/project
python3 scripts/model-policy.py install --target ~/.codex
python3 scripts/model-policy.py install --target /path/to/project/.codex --repo /path/to/project
python3 scripts/model-policy.py codex root --repo /path/to/project -- exec "summarize this repository"
```

For a machine-local change, create `${CODEX_HOME:-~/.codex}/model-policy.local.json`. For a project-only change, create `<repo>/.codex/model-policy.json`. For example:

```json
{"roles": {"explorer": {"model": "gpt-5.6-sol", "effort": "high"}}}
```

Then run the matching `install --target ...` command above. The resolver does not guess availability or silently downgrade an unavailable model; select a model/effort combination supported by the current host. Defaults use Astra ultra for CLI Root and `plan-challenger`, Terra high for exploration/implementation/final review roles, Luna low for command execution, and Sol high for branch review.

`plan-challenger` uses the planning tier for an independent, read-only challenge before a formal plan is finalized; it does not replace the final-code `verifier`. Claude inherits the planning Root's model via `core/agents/plan-challenger.md`; Codex resolves this role independently through the policy above. When changing the planning tier, check both `root` and `plan-challenger`; their policy entries do not automatically track each other. Trigger, bounded recheck, and unavailable-role handling belong to [plan-challenge](../core/skills/plan-challenge/SKILL.md).

`show` prints the effective model, effort, and source for both fields. `codex` launches the local Codex CLI through `execvp`, injecting `-m <model>` and `-c model_reasoning_effort=<effort>` without shell interpolation. Put wrapper overrides before `--`, for example `codex explorer --model gpt-5.6-sol --effort high -- exec ...`; they take precedence over every policy file. The `root` role controls this CLI entry point only; the Codex app model remains selected by its task UI.

`install` renders managed `agents/*.toml` from `core/agents/` templates and writes `.harness-models.json` in the target. The manifest records each generated role’s `agents/<role>.toml` path and SHA-256. A global installation has no `--repo`; a project override must use both `--repo /path/to/project` and `--target /path/to/project/.codex`, so one project’s policy cannot become a global role setting. It replaces only policy-known template roles and preserves unknown target roles; an existing managed file without a matching manifest hash is first backed up. If `agents` is a symlink, it moves that symlink to the supplied `--backup-dir` (or a timestamped `.model-policy-backups/` directory beside the target), then creates a real target directory; it never writes through the symlink into its source. Use `--dry-run` to print the pending backup and files.

```bash
python3 scripts/model-policy.py uninstall --target ~/.codex
```

`uninstall` only removes manifest-listed regular files whose current SHA-256 still matches. Modified, missing, symlinked, and unknown roles remain in place and are reported; a manifest with retained modified roles is kept for a later uninstall.

The helper locates `config/model-policy.json` and `agents/` beside its harness root. A copy placed in another harness also accepts `core/config/model-policy.json` and `core/agents/`, so the same script can run from Pele without a dependency on the private checkout. Template helper paths use `@HARNESS_ROOT@` and are rendered to that resolved root.

`scripts/harness-eval.py` lists six replayable, read-only fixtures by default. Use `--model` and `--effort` to run the identical set against a candidate; `--run` is the only mode that calls Codex. It uses a temporary `HOME` and Git repository while retaining the native `CODEX_HOME` only for Codex authentication, never copying or printing authentication files. The verified CLI placement is `codex exec [exec options] <prompt>`: each run passes `--ignore-user-config`, `--ignore-rules`, `--ephemeral`, `--output-schema`, `--output-last-message`, `--json`, read-only sandboxing, and disables hooks, project documents, and agents.

The evaluator reads correctness only from the JSON object written by `--output-last-message`; it never accepts text echoed in stdout or stderr. The JSON Schema requires `case_id`, `answer`, and `evidence`, and each fixture checks the exact answer and requires nonempty supporting evidence. JSONL event usage is recorded when present, otherwise `usage` is `null`. A case has a 180-second limit; failures and timeouts are recorded once without retry or model downgrade.
