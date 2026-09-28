#!/usr/bin/env bash
# N1 memory compaction helpers

# n1_compact_memory <memory_file> <sections_to_keep>
# Archives the full file and replaces it with a compacted version.
#
# 1. If <file>.full.md already exists, skip (never compact twice)
# 2. Copy <file> → <file>.full.md (archive)
# 3. Extract frontmatter (if any) and <!-- n1:signals --> block verbatim
# 4. Extract sections matching the keep-list (markdown ## headings)
# 5. Overwrite <file> with: frontmatter + kept sections + signals block
#
# sections_to_keep: comma-separated list of heading patterns (case-insensitive partial match)
# Example: "summary,conclusions,key decisions,acceptance criteria"
n1_compact_memory() {
    local file="$1" keep_list="$2"

    # 1. Skip if already compacted
    [ -f "${file}.full.md" ] && return 0

    # 2. File must exist
    [ -f "$file" ] || return 1

    # 3. Archive full content
    cp "$file" "${file}.full.md"

    # Write keep patterns to a temp file (one per line, lowercase, trimmed)
    local tmpkeep
    tmpkeep=$(mktemp)
    printf '%s\n' "$keep_list" | tr ',' '\n' | \
        awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print tolower($0) }' \
        > "$tmpkeep"

    # Single-pass awk:
    #   - Frontmatter (---...---) is passed through verbatim
    #   - Signals block (<!-- n1:signals ... -->) is collected and appended at the end
    #   - Level-2 and level-3 headings (## / ###) are independent section boundaries;
    #     each is evaluated against keep patterns regardless of nesting.
    #     Level-4+ headings (####...) inherit the keep status of their nearest ##/### ancestor.
    local tmp; tmp=$(mktemp "${file}.XXXXXX")
    awk -v kfile="$tmpkeep" '
    BEGIN {
        while ((getline line < kfile) > 0) {
            patterns[++np] = line
        }
        close(kfile)
        in_fm        = 0
        in_signals   = 0
        cur_keep     = 0
        cur_outer_lv = 0
        out_fm       = ""
        out_body     = ""
        out_sig      = ""
    }

    function hlevel(s,    i) {
        i = 0
        while (i < length(s) && substr(s, i + 1, 1) == "#") i++
        return i
    }

    function htext(s,    t) {
        t = s
        sub(/^#+[[:space:]]*/, "", t)
        return t
    }

    function matches(h,    i, hl) {
        hl = tolower(h)
        for (i = 1; i <= np; i++) {
            if (index(hl, patterns[i]) > 0) return 1
        }
        return 0
    }

    NR == 1 && /^---$/ { in_fm = 1; out_fm = out_fm $0 "\n"; next }
    in_fm && /^---$/   { in_fm = 0; out_fm = out_fm $0 "\n"; next }
    in_fm              { out_fm = out_fm $0 "\n"; next }

    /^<!-- n1:signals/ { in_signals = 1; out_sig = out_sig $0 "\n"; next }
    /^<!-- \/n1:signals/ { out_sig = out_sig $0 "\n"; in_signals = 0; next }
    in_signals {
        out_sig = out_sig $0 "\n"
        if (/^-->$/) in_signals = 0
        next
    }

    /^#{2,}[[:space:]]/ {
        lv = hlevel($0)
        ht = htext($0)
        if (lv <= 3) {
            cur_outer_lv = lv
            cur_keep     = matches(ht)
        } else if (cur_outer_lv == 0) {
            cur_outer_lv = lv
            cur_keep     = matches(ht)
        }
        # lv >= 4 with cur_outer_lv set: inherit cur_keep from parent
        if (cur_keep) out_body = out_body $0 "\n"
        next
    }

    { if (cur_keep) out_body = out_body $0 "\n" }

    END {
        printf "%s", out_fm
        printf "%s", out_body
        if (out_sig != "") printf "%s", out_sig
    }
    ' "$file" > "$tmp"

    # Safety net: abort compaction if output < 20% of input
    local in_size out_size
    in_size=$(wc -c < "$file")
    out_size=$(wc -c < "$tmp")
    if [ "$in_size" -gt 0 ] && [ $((out_size * 100 / in_size)) -lt 20 ]; then
        echo "n1_compact_memory: output is ${out_size}/${in_size} bytes (<20%), aborting compaction" >&2
        rm -f "$tmp" "${file}.full.md"
        rm -f "$tmpkeep"
        return 1
    fi

    mv "$tmp" "$file"

    rm -f "$tmpkeep"
}

# n1_append_key_decision <overview_path> <decision_text>
# Appends a bullet entry to the ## Key Decisions section of an overview file.
#
# Behavior:
#   - If ## Key Decisions is found and contains "(none yet)", replaces that line
#     with "- <decision_text>"
#   - If ## Key Decisions is found without "(none yet)", appends "- <decision_text>"
#     after the last content line of the section (before the next ## heading or EOF)
#   - If ## Key Decisions is absent, creates the section before ## Escalations
#     (or at EOF if ## Escalations is also absent)
# No deduplication — entries are event-style.
n1_append_key_decision() {
    local file="$1" text="$2"

    [ -f "$file" ] || return 1
    [ -n "$text" ] || return 1

    local tmp; tmp=$(mktemp "${file}.XXXXXX")
    awk -v entry="- ${text}" '
    BEGIN {
        found_section = 0
        in_section    = 0
        replaced_none = 0
        section_end   = -1
        n              = 0
    }

    {
        lines[n] = $0
        n++
    }

    END {
        # Locate the ## Key Decisions section
        sec_start = -1
        sec_end   = -1
        for (i = 0; i < n; i++) {
            if (lines[i] ~ /^## Key Decisions[[:space:]]*$/) {
                sec_start = i
                continue
            }
            if (sec_start >= 0 && sec_end < 0 && i > sec_start && lines[i] ~ /^## /) {
                sec_end = i
                break
            }
        }
        if (sec_start >= 0 && sec_end < 0) sec_end = n  # section runs to EOF

        if (sec_start >= 0) {
            # Check for "(none yet)" placeholder
            none_idx = -1
            for (i = sec_start + 1; i < sec_end; i++) {
                if (index(lines[i], "(none yet)") > 0) {
                    none_idx = i
                    break
                }
            }
            if (none_idx >= 0) {
                # Replace placeholder line
                for (i = 0; i < n; i++) {
                    if (i == none_idx) print entry
                    else print lines[i]
                }
            } else {
                # Append after last non-blank line in section (before sec_end)
                last_content = sec_start  # fallback: right after heading
                for (i = sec_start + 1; i < sec_end; i++) {
                    if (lines[i] !~ /^[[:space:]]*$/) last_content = i
                }
                insert_after = (last_content > sec_start) ? last_content : sec_start
                for (i = 0; i < n; i++) {
                    print lines[i]
                    if (i == insert_after) print entry
                }
            }
        } else {
            # Section absent — find ## Escalations or use EOF
            esc_idx = -1
            for (i = 0; i < n; i++) {
                if (lines[i] ~ /^## Escalations[[:space:]]*$/) {
                    esc_idx = i
                    break
                }
            }
            if (esc_idx >= 0) {
                # Insert new section before ## Escalations
                for (i = 0; i < esc_idx; i++) print lines[i]
                print ""
                print "## Key Decisions"
                print entry
                print ""
                for (i = esc_idx; i < n; i++) print lines[i]
            } else {
                # Append at EOF
                for (i = 0; i < n; i++) print lines[i]
                print ""
                print "## Key Decisions"
                print entry
            }
        }
    }
    ' "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; false; }
}

# n1_extract_sections <file> <heading_regex>...
# Prints each ## or ### section whose heading text matches one of the regexes (case-insensitive ERE),
# including nested lower-level headings, up to the next heading of the same or higher level.
n1_extract_sections() {
    local file="$1"; shift
    [ -f "$file" ] || return 0
    local pattern
    pattern=$(printf '%s|' "$@"); pattern="${pattern%|}"
    awk -v pat="$pattern" '
        function level(line) { match(line, /^#+/); return RLENGTH }
        /^#{2,3} / {
            text=$0; sub(/^#+[[:space:]]*/, "", text)
            if (printing && level($0) <= plevel) { printing=0; if (last != "") print ""; last="" }
            if (!printing && tolower(text) ~ tolower(pat)) { printing=1; plevel=level($0); print; last=$0; next }
        }
        printing { print; last=$0 }
        END { if (printing && last != "") print "" }
    ' "$file"
}

# _n1_title_words — stdin → unique lowercase [a-z0-9] words of length >= 3, one per line (C-sorted).
_n1_title_words() {
    { LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C grep -oE '[a-z0-9]{3,}' || true; } | LC_ALL=C sort -u
}

# n1_memory_reuse_check <memory_dir> <fresh_title>
# Ticket-ID reuse guard (NP-235). When <memory_dir> holds a finished run (overview.md `step: done`)
# and fewer than 60% of <fresh_title>'s words appear in the stored ticket.md (fallback: overview H1),
# moves the dir to <dir>-old (then -old-2 .. -old-50, never overwriting) and prints the new path.
# Prints nothing and leaves memory untouched otherwise, including any empty/missing input
# (fail open to "related"). Returns non-zero only if mv fails.
n1_memory_reuse_check() {
    local dir="${1%/}" fresh="${2:-}" ov step fwords stored total hits n target
    ov="$dir/overview.md"
    [ -f "$ov" ] || return 0
    # Reuse the existing frontmatter reader (handles the frontmatter block + CRLF strip)
    # instead of a second hand-rolled parser — same idiom as lib/cache.sh:66.
    source "$(dirname "${BASH_SOURCE[0]}")/frontmatter.sh"
    step=$(n1_read_frontmatter "$ov" step)
    [ "$step" = "done" ] || return 0
    fwords=$(printf '%s\n' "$fresh" | _n1_title_words)
    [ -n "$fwords" ] || return 0
    if [ -s "$dir/ticket.md" ]; then
        stored=$(_n1_title_words < "$dir/ticket.md")
    else
        stored=$({ grep -m1 '^# ' "$ov" || true; } | _n1_title_words)
    fi
    [ -n "$stored" ] || return 0
    total=$(printf '%s\n' "$fwords" | wc -l)
    hits=$(LC_ALL=C comm -12 <(printf '%s\n' "$fwords") <(printf '%s\n' "$stored") | wc -l)
    # ponytail: containment >= 0.6 calibrated on 16 N1 tickets (0 self false-archives, some unrelated
    # pairs kept as related = safe direction); tune this ratio if reuse detection misfires.
    [ $(( hits * 10 )) -ge $(( total * 6 )) ] && return 0
    for n in $(seq 1 50); do
        target="${dir}-old"; [ "$n" -gt 1 ] && target="${target}-${n}"
        [ -e "$target" ] && continue
        mv "$dir" "$target" || return 1
        printf '%s\n' "$target"
        return 0
    done
    echo "n1_memory_reuse_check: ${dir}-old .. -old-50 all taken; leaving $dir untouched" >&2
    return 0
}

# n1_archive_stale_branch <branch> <suffix>
# NP-235 CR-1: after n1_memory_reuse_check archives memory for a reused ticket ID, the stale
# working branch/worktree left over from the finished run must not be reused by the new ticket.
# Mirrors the memory archive: rename only, never delete.
#   - Worktree with <branch> checked out (per `git worktree list --porcelain`): moved to
#     <path><suffix>. Move failure -> warn to stderr, return 1 (branch is left untouched).
#   - Branch <branch> exists: renamed to <branch><suffix> (`git branch -m`, never -M).
#     Target name already taken -> warn to stderr, return 1.
#   - Neither exists -> no-op, return 0.
# Prints the new branch name on success.
n1_archive_stale_branch() {
    local branch="$1" suffix="$2"
    [ -n "$branch" ] && [ -n "$suffix" ] || return 0

    local wt_path="" cur_path=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) cur_path="${line#worktree }" ;;
            "branch refs/heads/$branch") wt_path="$cur_path" ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null || true)

    if [ -n "$wt_path" ] && ! git worktree move "$wt_path" "${wt_path}${suffix}" 2>/dev/null; then
        echo "n1_archive_stale_branch: failed to move worktree $wt_path to ${wt_path}${suffix}" >&2
        return 1
    fi

    git show-ref --verify --quiet "refs/heads/$branch" || return 0

    if git show-ref --verify --quiet "refs/heads/${branch}${suffix}"; then
        echo "n1_archive_stale_branch: target branch ${branch}${suffix} already exists; leaving $branch intact" >&2
        return 1
    fi
    if ! git branch -m "$branch" "${branch}${suffix}" 2>/dev/null; then
        echo "n1_archive_stale_branch: failed to rename branch $branch to ${branch}${suffix}" >&2
        return 1
    fi
    printf '%s\n' "${branch}${suffix}"
}
