# Claude Usage Policy & Billing Guidance
**Effective:** August 2026 (per Nicole Stonehouse, Claude Admin)  
**Copy this to each project's memory system or reference it as a guide**

---

## ⛔ MODEL POLICY

- **DO NOT USE FABLE** — Results in complete access revocation
- **DEFAULT:** Haiku 4.5 for all routine work
- **ESCALATE TO:** Sonnet/Opus only for complex reasoning, code review, or agent-heavy operations
- **WHY:** Cost efficiency + enforced monthly spending caps

---

## 💰 MONTHLY BILLING CAPS (Hard Limits)

| User Tier | Monthly Cap | Overage Process |
|-----------|-------------|-----------------|
| Standard | $25 | Increase request goes to Phoutty (Teams/email) with strong and valid justification |
| Premium | $125 | Increase request goes to Phoutty (Teams/email) with strong and valid justification |

**Justification Examples:**
- "Multi-day agent-based code consolidation analysis for [client] engagement"
- "Enterprise architecture audit across 5 codebases"
- "Security compliance review requiring extensive file analysis"

---

## 🎯 HOW TO STAY IN BUDGET

1. **Check model at session start** — Confirm Haiku is selected
2. **Break large work into sessions** — Don't run 3 agents + 20K token reads in one go
3. **Monitor token usage** — If session is >100K tokens, plan next session separately
4. **Escalate early** — If approaching cap mid-month, pause and request increase before proceeding

---

## 📋 FOR PROJECT-SPECIFIC MEMORY

Save this as `feedback_claude_usage_policy.md` in your project's memory folder:

```markdown
---
name: claude_usage_policy
description: NO Fable; Haiku default; $25/$125 caps; justify overages to Phoutty
metadata:
  type: feedback
---

**Rule:** Never use Fable model (access revocation). Default Haiku. Escalate to Sonnet/Opus only for complex reasoning/code review.

**Billing:** Standard $25/mo cap, Premium $125/mo cap. Justify increases to Phoutty.

**Stay in budget:** Break work into sessions, confirm model at start, escalate early if approaching cap.
```

Then add to your project's `MEMORY.md`:
```
- [Claude usage policy](feedback_claude_usage_policy.md) — NO Fable; Haiku default; $25/$125 caps; justify overages
```

---

## 📞 FOR ACCOUNT-LEVEL SETUP

If you want this enforced globally across ALL projects (not per-project):

**Contact:** Nicole Stonehouse (Claude Admin) or Phoutty  
**Ask for:** Account-level Claude Code configuration, startup reminder hook, or global guardrails on model selection  
**Example:** "Can we set a default to Haiku and require justification before Sonnet/Opus selection?"

---

## 🔗 PROJECTS THIS APPLIES TO

- FCB Kafka Consultation (flink-on-k8s-with-cp) ✅
- Fox Entertainment Moveworks→Serval engagement (consulting scope)
- Any other consulting/internal R&D projects

---

**Last Updated:** 2026-08-04  
**Source:** Nicole Stonehouse announcement, Claude Users channel
