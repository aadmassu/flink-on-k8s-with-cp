# Deliverables — where engineers submit weekly work

Each engineer gets their own folder here. Suggested structure:

```
deliverables/
├── README.md            ← you are here
├── <engineer-name>/
│   ├── week01/
│   │   ├── monday.md
│   │   ├── tuesday.md
│   │   ├── wednesday.md
│   │   ├── thursday.md
│   │   ├── friday-troubleshooting-checklist.md
│   │   └── week-01-runbook.md          ← week-end deliverable per Week 1 README
│   ├── week02/
│   ├── week03/
│   ├── week04/
│   ├── week05/
│   └── week06/
│       ├── ...
│       ├── mrc-topology.drawio          ← THE end-of-bootcamp diagram
│       └── final-demo-link.md           ← link or path to the end-to-end demo recording
```

## Naming convention

- One folder per engineer: lowercase, hyphenated (e.g. `asmerom-tesfaye/`, `jay-patel/`)
- One file per day, named after the day (`monday.md`, `tuesday.md`, ...)
- Friday's file gets a more descriptive name when it's the troubleshooting checklist (`friday-troubleshooting-checklist.md`) — so it's findable later
- Week-end deliverables are named `week-NN-<thing>.md`

## Why commit them?

Three reasons:

1. **Review** — Ayu / senior engineers can review the runbooks + checklists + flag misunderstandings before they compound
2. **Pattern recognition** — the troubleshooting checklists from 6 engineers, side by side, surface the failure modes that matter most. Aggregate into the team's actual on-call runbook.
3. **Repeatable bootcamp** — next engineer onboards, they can read the previous cohort's deliverables and skip ahead on the easy stuff

## Final deliverable package (end of Week 6)

By Friday EOD of Week 6, each engineer's `<engineer-name>/` folder should have:

1. **OpenShift Troubleshooting Runbook** — composite of Friday-troubleshooting-checklist files from all 6 weeks
2. **CFK Deployment Guide** — composite of Week 4 deliverables
3. **Kafka Operations Guide** — composite of Week 5 deliverables
4. **OAuth/OIDC Troubleshooting Guide** — from Week 3 Tuesday + Week 5 Wednesday
5. **Monitoring Dashboard Package** — Grafana JSON exports + how-to-import.md
6. **Multi-Region DR Runbook** — from Week 6 Friday
7. **Final Architecture Diagram Set** — drawio originals + PNG exports for every drawio they touched

Ayu signs off on each engineer's final package before they're considered bootcamp-graduated. Sign-off is a 30-min walkthrough where the engineer demos one failure scenario from their troubleshooting checklist live.
