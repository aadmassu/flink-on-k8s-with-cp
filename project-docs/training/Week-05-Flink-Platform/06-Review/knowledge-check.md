# Week 5 — Knowledge Check

Concept-level self-quiz. Answer in your own words; if you can't answer without looking, re-read the referenced day.

## Architecture (Monday)

1. What does "stateful streaming" mean, and where does the state physically live in a running Flink job?
2. Flink treats batch as bounded streaming. Give one operational advantage and one operational cost of that unified model.
3. Name the 4 top-level components of a running Flink cluster and one job each does.

## Operator (Tuesday)

4. What's the difference between `FlinkDeployment` and `FlinkSessionJob` — when do you use each?
5. Name three Kubernetes resources the Flink operator creates on your behalf when you `oc apply` a `FlinkDeployment`.
6. In `savepoint` upgrade mode, walk the state transitions your job goes through.

## Runtime (Wednesday)

7. What's a "slot" vs "parallelism" vs "task chain" — how are they related?
8. Given `taskManager.replicas=3`, `numberOfTaskSlots=4`, `job.parallelism=8` — how many slots are used, how many free?
9. If one TM's CPU is at 100% while others are idle, what's the most likely cause and how do you fix it?

## Enterprise Components (Thursday)

10. If CMF goes down for 30 min, what happens to a currently-running Flink job's data flow? Explain why.

---

Self-scoring: **10 correct** = fluent; **7-9** = strong; **≤ 6** = pick the weakest area and reread the day.
