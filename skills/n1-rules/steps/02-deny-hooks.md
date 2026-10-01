<!-- Purpose: Deny hook generation (add command step 9), check command, check --fix command. -->

## Add Command: Step 9 — Deny Hook Generation

When enforcement is `deny`, report: "Generated deny hooks are unsupported in Codex milestone 1. The rule is saved without tool-call enforcement; existing shared rules-deny.sh and Claude settings remain unchanged." **STOP this sub-flow before creating directories, generating/registering/deregistering hooks, or deleting hook files.** Continue only to the rule summary below.

**10. Summary:**
```
Rule created: {name}.rule.md
  Description: {description}
  Topic: {topic}
  Applies to: {agents}
  Enforcement: {enforcement}
  Location: {RULES_DIR}/{name}.rule.md
```

---

## Command: `check`

Validate all rules. Report issues as warnings or errors.

```bash
RULES_DIR=$(n1_rules_dir)
```

If no rules directory or empty: "No rules to check." **STOP.**

For each rule file:

**Required fields:** `description`, `topic`, `applies_to`, `enforcement`
- Missing field → ERROR: "Rule `{name}` missing required field: `{field}`"

**Topic validation:** must be one of: `code-style`, `testing`, `security`, `architecture`, `process`, `writing`, `ops`
- Invalid → ERROR: "Rule `{name}` has invalid topic: `{value}`"

**Enforcement validation:** must be `deny` or `gate`
- Invalid → ERROR: "Rule `{name}` has invalid enforcement: `{value}`"

**`applies_to: *` warning:**
- WARN: "Rule `{name}` applies to every persona — consider whether it belongs in AGENTS.md instead."

**Gate rule positive phrasing:**
- If body starts with "Do not"/"Never"/"Don't"/"Must not"/"Avoid" → WARN: "Rule `{name}` uses negative phrasing. Gate rules should state what TO do — LLM reviewers are weak on negation."

**Deny rule predicate check:**
- If enforcement is `deny` but neither `deny.paths` nor `deny.commands` exists → ERROR: "Rule `{name}` is `deny` but has no deny predicates (paths or commands). Add deny.paths or deny.commands, or change to gate."

**Count warning:**
- If total rules > 10 → WARN: "⚠ {N} rules — research shows >10 blocking rules risk degrading task success. Consider consolidating."

**Report:**
```
Checked {N} rules: {errors} errors, {warnings} warnings.
```

---

## Command: `check --fix`

Run only the read-only checks from the `check` command above. Then report: "Deny-hook repair is unsupported in Codex milestone 1. Existing shared rules-deny.sh and Claude settings remain unchanged." **STOP before any hook-directory creation, generation, registration, deregistration, or deletion.**
