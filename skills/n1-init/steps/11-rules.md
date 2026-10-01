<!-- Purpose: Generate starter project rules and optionally migrate AGENTS.md behavioral conventions. -->

## Rules Configuration

Ask whether N1 should generate project rules — authored, checkable conventions that drive review gates. Generated deny hooks are unsupported in Codex milestone 1. Preserve existing shared deny-hook files and Claude settings. **Default is Yes** for new setups, presented after all other config is written.

```
N1 can generate project rules from what it detects about your project.
Gate rules block reviews. Deny rules can be stored, but their tool-call enforcement is unsupported in Codex milestone 1.
1 — Yes, generate starter rules (recommended)
2 — No, skip rules for now
```

**If 2 (No) or skip:** Write `"rules": { "enabled": true }` to config and move on. No rules directory created.

**If 1 (Yes):**

1. Set `RULES_DIR="$N1_HOME/rules"`. Write `"rules": { "enabled": true }` to config.

2. Create the rules directory: `mkdir -p "$RULES_DIR"`

2b. **Seed default rules.** Scan `<N1_ROOT>/defaults/rules/` for `.rule.md` files. For each file, check whether a rule with the same basename already exists in `$RULES_DIR/`. If it does, skip silently. If it does not, present it using the same Accept/Edit/Skip UX as detection-based rules:

   ```
   Default rule: <name>
     Description: <description field>
     Topic: <topic field>
     Applies to: <applies_to field>
     Enforcement: <enforcement field>
     Body:
       <rule body text>

   1 — Accept
   2 — Edit (modify before saving)
   3 — Skip
   ```

   - **1 (Accept):** Copy the file to `$RULES_DIR/<name>.rule.md`
   - **2 (Edit):** Let the user modify the description, body, and enforcement, then write the edited version
   - **3 (Skip):** Do not create this rule

   Default rules are presented before detection-based rules so universal conventions appear first.

3. Generate starter rules from existing detection results. For each detected characteristic, propose a rule with enforcement recommendation. Present **one at a time** for approval:

   **From lockfile/package manager detection:**
   - Propose a `deny` rule if a lockfile exists: "no direct edits to `<lockfile>`" with `deny.paths: ["<lockfile>"]`
     - `topic: ops`, `applies_to: [developer, implementer]`, `enforcement: deny`

   **From analysis cache snapshot (when available):**
   - If `$N1_HOME/cache/project-snapshot.md` exists, read its conventions section and propose `gate` rules for any convention that is checkable

   For each proposed rule, show:
   ```
   Proposed rule: <name>
     Description: <one-line>
     Topic: <topic>
     Applies to: <agents>
     Enforcement: <deny|gate>
     Body:
       <rule text>

   1 — Accept
   2 — Edit (modify before saving)
   3 — Skip
   ```

   - **1 (Accept):** Write the rule file to `$RULES_DIR/<name>.rule.md`
   - **2 (Edit):** Let the user modify the description, body, and enforcement, then write
   - **3 (Skip):** Do not create this rule

4. After all proposals: show count of accepted rules. If > 10, warn about cost-of-compliance.

5. If any accepted rules have `enforcement: deny`, report: "Generated deny hooks are unsupported in Codex milestone 1; deny rules were saved without tool-call enforcement. Existing shared rules-deny.sh and Claude settings remain unchanged." **STOP the deny-hook sub-flow before creating hook directories, generating, registering, deregistering, or deleting hooks.** Continue with gate-rule setup and the remaining init steps.

### AGENTS.md Convention Migration (conditional)

**Only show this section when at least one rule was created in the Rules Configuration step above.**

Scan AGENTS.md for behavioral convention blocks — lines that prescribe behavior (imperative mood: "always", "never", "must", "use X for Y") rather than state facts. For each identified block:

```
Found behavioral convention in AGENTS.md:

  > <quoted block>

This could become a rule. Extract it?
1 — Yes, extract as gate rule
2 — Yes, extract as deny rule (if mechanically checkable)
3 — No, leave in AGENTS.md
```

- **2:** Report that deny enforcement is unsupported in Codex milestone 1. Keep the behavioral convention in AGENTS.md and stop this extraction sub-flow before any hook action.
- **1:** Create a gate rule file, ask for `applies_to`, then ask:
  ```
  Remove this convention from AGENTS.md now that it's a rule?
  1 — Yes, remove from AGENTS.md
  2 — No, keep in both places
  ```
- **3:** Leave in place

**Do NOT add any "Project Rules" section to AGENTS.md.** Do NOT remove factual content — only behavioral prescriptions the user explicitly chose to remove.

### On reconfiguration (n1-init re-run):

If `rules` already exists in the current config:

```
Current rules:
  count → <N> rules

1 — Keep current
2 — Re-generate starter rules (adds to existing, does not delete)
```

- **1** → leave unchanged.
- **2** → re-run default rule seeding (step 2b) and detection-based rule generation (step 3). Both skip rules that already exist by name in `$RULES_DIR/`.

**Legacy repo rules:** If rules exist at `<root>/.n1/rules/`, report their location and leave them in place. Codex does not migrate shared state or regenerate/deregister legacy deny hooks; use the original N1 plugin for that operation.

If `rules` is absent from the current config, run the fresh-setup flow above. Run **Analyze Repository** first if it has not already been run this session (rules starter generation needs detection results).
