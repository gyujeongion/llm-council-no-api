# claude-code-council

**Stop letting one AI grade its own homework.**

`/council` is a [Claude Code](https://claude.com/claude-code) skill. It runs the same
question through two other models, Gemini and GPT, as local CLIs, then has Claude
compare their answers and give a verdict. Under the hood it's `gemini -p` plus
`codex exec`, with Claude doing the framing and the synthesis. The dressed-up version:
Claude chairs a panel and the panel has no stake in Claude being right.

The panel calls run through CLIs you already log into (`gemini` and `codex`), so they
**don't spend any extra API keys** — they draw on your existing Gemini and Codex CLI
sessions. (Claude still spends its own tokens framing the prompt and synthesizing the
replies; see [What it actually costs](#what-it-actually-costs).)

```
You:     /council is this migration plan safe?

Claude:  [asks Gemini and GPT in parallel...]

         ✅ Both agree: the down-migration is missing a backfill step.
         ⚠️ Disagreement: Gemini wants a feature flag; GPT says ship behind a
            transaction. (GPT) is right here because your DB supports DDL in tx.
         Verdict (Claude — chair): add the backfill, wrap in a transaction,
            skip the flag. Here's the corrected plan...
```

> Real panel output is longer and messier than this. Models ramble, sometimes
> disagree on the wrong thing, and occasionally one refuses. The chairman's job is
> to cut through that — the value is in the reconciliation, not in any single reply.

---

![council demo](demo/council.gif)

## Why

A model is wrong most often where it can't see its own blind spots. A second model
that had no part in the first answer is the cheapest way to catch that. This skill
makes it a one-command habit instead of three browser tabs and copy-paste.

- **No extra API keys.** It calls the `gemini` and `codex` CLIs you've already
  authenticated, not a paid API endpoint.
- **No browser automation, no scraping, no token extraction.** It only shells out to
  the CLIs you installed. (See [Responsible use](#responsible-use).)
- **Graceful degradation.** Only have one of the two CLIs? The council still
  convenes with one panelist.

It's a thin wrapper, and it's honest about that. The value isn't clever
infrastructure — it's making "go ask two other models and reconcile the answers" a
single command you'll actually use.

---

## Install

### 1. Install at least one panel CLI

| Panel | CLI | Get it |
|---|---|---|
| Gemini | `gemini` | [gemini-cli](https://github.com/google-gemini/gemini-cli), then run `gemini` once to log in |
| GPT | `codex` | [OpenAI Codex CLI](https://github.com/openai/codex) (the 2025 agentic CLI, not the retired 2021 Codex model), then run `codex login` |

You need **one or both**. The skill works with whichever are present. If a CLI isn't
installed or logged in, that seat is simply empty and the council runs with the rest.

### 2. Drop the skill into Claude Code

```bash
git clone https://github.com/<you>/claude-code-council.git
cp -r claude-code-council/skills/council ~/.claude/skills/council
cp -r claude-code-council/bin           ~/.claude/skills/council/bin
chmod +x ~/.claude/skills/council/bin/*.sh
```

> The skill resolves `bin/ask.sh` relative to its own directory, so keep `bin/`
> next to `SKILL.md`.

### 3. Verify

```bash
~/.claude/skills/council/bin/doctor.sh --smoke
```

You should see a ✓ and a live `OK` from each installed panel.

---

## Usage

In Claude Code, just talk to it:

- `/council review this function for race conditions`
- `council — is this architecture decision sound?`
- `get a second opinion on this approach`
- `have Gemini and GPT stress-test this plan`

Claude (the chairman) will:

1. Frame one clear prompt and send the **identical** question to both panels in parallel.
2. Collect their independent answers.
3. Synthesize: **agreements → disagreements → its own verdict**, attributing every
   claim to `(Gemini)`, `(GPT)`, or `(Claude — chair)`.

For code/design questions, paste the **relevant diff or snippet** into the prompt so the
panels judge the actual code, not a paraphrase (scoped, and with secrets stripped — see
the skill's redaction rule). For hard, multi-faceted calls you can also give each panel a
**different lens** (Gemini → architecture/maintainability, GPT → edge cases/bugs) instead
of the same prompt, so two passes cover more ground than one repeated. The same-prompt
default stays best for a clean agree/disagree signal.

### Configuration

All optional — override via environment variables:

| Var | Default | Purpose |
|---|---|---|
| `COUNCIL_GEMINI_BIN` | `gemini` | path/name of the Gemini CLI |
| `COUNCIL_GPT_BIN` | `codex` | path/name of the GPT CLI |
| `COUNCIL_GEMINI_MODEL` | — | passed to `gemini --model` |
| `COUNCIL_GPT_MODEL` | — | passed to `codex -m` |
| `COUNCIL_GPT_TIMEOUT` | `180` | seconds before a GPT call is abandoned |

---

## How it works

```
                 ┌─────────────────────────┐
   your prompt → │   Claude  (chairman)    │
                 └───────────┬─────────────┘
                  same prompt │ in parallel
              ┌───────────────┴───────────────┐
              ▼                               ▼
       bin/ask.sh gemini              bin/ask.sh gpt
        → gemini -p                   → codex exec -s read-only
              │                               │
              └───────────────┬───────────────┘
                              ▼
                 ┌─────────────────────────┐
                 │ Claude synthesizes:     │
                 │  • agreements           │
                 │  • disagreements        │
                 │  • its own verdict      │
                 └─────────────────────────┘
```

`bin/ask.sh` is a thin, portable wrapper. It finds each CLI via `which` (or an
override env var), calls it non-interactively, and returns clean text. That's the
whole job.

---

## What gets sent

This matters most when you're reviewing real code, so here it is plainly:

- A panel sees **exactly the one prompt the chairman passes to `ask.sh`** — nothing
  more. There's no automatic crawling of your repo, no file attachment, no hidden
  context bundle.
- If Claude decides a code snippet is needed for the review, it puts that snippet
  **in the prompt text** — so it's visible in the same command you'd see in Claude
  Code. Nothing is sent that isn't in that prompt string.
- `codex` is an agentic CLI that *can* read files in its working directory. To stop
  it reaching your repo, `ask.sh` runs it from an **empty temp directory** (created
  per call, deleted after). It literally has nothing to read but the prompt. This is
  enforced in code (`bin/ask.sh`, the `gpt` branch), not just promised here. It also
  passes `-s read-only`, codex's own sandbox flag for preventing writes and command
  execution (the exact guarantees are codex's to define and may vary by version).
- Whatever *is* in the prompt leaves your machine and goes to Google / OpenAI under
  their terms. **Don't put secrets, credentials, or confidential data in a council
  question.** The skill instructions enforce this, but treat it as your call.

If you need a model to review proprietary code you can't send to third parties, this
skill is the wrong tool — keep that review inside Claude alone.

## What it actually costs

The honest accounting, because "free" gets thrown around too easily:

- **Panel calls:** no Claude tokens, no separate API key. They draw on your existing
  `gemini` and `codex` CLI sessions, and are subject to **those providers' quotas,
  rate limits, and terms**. Hammer them in a loop and you'll hit limits.
- **Claude's own tokens:** still spent. Claude writes the prompt and then reads both
  panel replies back into its context to synthesize — so a council call costs *more*
  Claude tokens than just asking Claude directly. You're trading tokens for a
  cross-check, not getting one for free.

The pitch isn't "free AI." It's "a second and third opinion without juggling tabs or
wiring up paid API keys."

---

## Responsible use

This project does **not** bypass provider limits, scrape private endpoints, or
extract OAuth tokens. It only shells out to **locally installed, officially
authenticated CLI tools** that you set up yourself. Availability, quotas, and
terms of service are controlled by each provider (Google, OpenAI) and may change
at any time.

**On attack surface:** this skill adds none beyond the CLIs you already installed and
logged into. It never grants them extra access. In fact it runs `codex` *more*
narrowly than a normal session — `-s read-only` (codex's sandbox flag for preventing
writes and execution) inside a throwaway empty directory. A panel returns text for
the chairman to read; it isn't given a path to act on your repo. If you don't trust the `gemini` or
`codex` CLIs to run on your host at all, that's a decision to make about those tools
themselves — this wrapper only ever tightens their sandbox, never loosens it.

- Use it for personal and experimental workflows.
- Review each provider's terms before relying on it for production or team use.
- **Never send secrets, credentials, or confidential data to a panel** — anything
  you ask leaves your machine and goes to a third-party model. The skill's
  instructions enforce this, but it's ultimately on you.

---

## Limitations (read before you rely on it)

No pretending here — these are real and you should know them going in:

- **It rides on third-party CLIs.** `ask.sh` calls the **official non-interactive
  modes** (`gemini -p`, `codex exec`), not screen-scraping of a spinner — so it's
  more stable than wrapping an interactive TUI. But these are still external tools on
  their own release schedule. A flag rename in a future `gemini` or `codex` can break
  a panel until `ask.sh` gets a one-line patch. `doctor.sh --smoke` tells you in two
  seconds whether each panel still works.
- **The chairman is still one model.** Claude frames the question and arbitrates the
  answers, so a badly framed prompt or an over-trusted panelist can still mislead it.
  The council widens the blind spot; it doesn't abolish it.
- **Quotas are real.** Panel calls spend your Gemini/Codex subscription quota. Run it
  in a tight loop and you'll get rate-limited. It's built for deliberate "check this
  decision" moments, not bulk automation.
- **Not for code you can't share.** Anything in the prompt goes to Google/OpenAI. For
  truly proprietary review, keep it inside Claude alone.

Found a broken flag or a sharp edge? PRs and issues welcome.

---

## Prior art

The "convene other models for a second opinion" idea isn't new, and this didn't invent
it — tools like [the-council](https://github.com/DantesPeak85/the-council) and
[ai-pair](https://github.com/axtonliu/ai-pair) explore the same space, and the
diff/snippet-in-context and per-panel-lens ideas were sharpened by looking at them. What
this one leans on: **no API keys** (it rides your already-authenticated `gemini`/`codex`
CLIs), an **enforced privacy boundary** for the codex panel (empty temp dir, in code),
and a chairman that **synthesizes rather than vote-counts**. If those don't matter to
you, the tools above may fit better — pick what works.

---

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Anthropic, Google, or OpenAI. "Claude", "Gemini", and "GPT"
are trademarks of their respective owners.
