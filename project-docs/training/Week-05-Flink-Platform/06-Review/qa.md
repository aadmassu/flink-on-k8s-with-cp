# Week 5 — Q&A Bank

20 questions from the week to reinforce key concepts. Try to answer each in one paragraph before checking the referenced day.

## Monday — Flink Architecture

1. What makes a Flink job "stateful" — where does the state physically live between events?
2. If Flink treats batch as bounded streaming, why does the SQL syntax often distinguish them?
3. What's the smallest possible Flink deployment that can run one keyed-window job?
4. Who submits a job to the JobManager in FCB production?

## Tuesday — Flink Operator

5. What's the difference between a FlinkDeployment application cluster and a FlinkSessionJob targeting a session cluster?
6. Why does the Flink operator use Deployments and not StatefulSets, when CFK uses StatefulSets for Kafka brokers?
7. If you edit `spec.job.parallelism` from 4 to 8, does the operator restart the job immediately?
8. In FCB HA setup, what happens if the K8s API server is briefly unreachable — does the JobManager fail over?

## Wednesday — Flink Runtime

9. Why is "parallelism" a job-level setting but slots are a TM-level setting?
10. What actually gets put in a slot — a whole operator? A partial DAG chain? An event?
11. When would you deliberately disable operator chaining, given that chaining is more efficient?
12. Where does the JM get the "list of TMs and their slot capacity" — push or pull?

## Thursday — Enterprise Components

13. If CMF goes down, do already-running Flink jobs continue processing? Explain why.
14. What's the difference between a checkpoint and a savepoint in *what they store*?
15. Why does FCB use SQL Server for CMF's backend instead of the in-cluster PostgreSQL?
16. If Artifactory is down when a job Pod starts, what happens — CR stuck, failed, or retry?
17. In Kubernetes-native HA, where is the leader lease physically stored, and what's the granularity of failover?

## Friday — End-to-End Deployment

18. Order these by "closest to the developer" → "closest to the JVM": Artifactory, JobManager, CMF, Flink Operator, kube-apiserver, Kafka.
19. Where in the flow does OAuth first come into play — at CR apply, at Pod startup, at Kafka source connection, or at checkpoint write?
20. What's the single change that would make an end-to-end deploy fastest to iterate — where's the current bottleneck?

---

## How to use this

Cover the question, write your answer in 3-5 sentences, then check yourself against the referenced day's discussion.md. Anywhere your answer doesn't match: reread that section.
