# Week 5 Wednesday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. Why is "parallelism" a job-level setting but slots are a TM-level setting — what's the mismatch about?

They describe two different things:

- **Parallelism** = how many parallel instances of each operator the *job* wants to run
- **Slot** = the TM's unit of execution capacity

The mismatch the JM has to solve at deploy: fit `parallelism` parallel instances into the available slot pool, accounting for chained operators sharing slots. If `parallelism > total_slots`, the job stays in `CREATED` waiting for slot resources. If `parallelism < total_slots`, capacity is unused. Slot sharing (multiple chains from different keys sharing one slot) lets one job's total slot need drop below its parallelism.

Rule of thumb: `total_slots = TM_replicas × slots_per_TM` must be ≥ the job's largest per-slot-group parallelism.

## 2. What actually gets put in a slot — a whole operator, a partial DAG chain, or an event?

A **task**, where a task = one parallel instance of one **operator chain**. The planner fuses chainable operators (same key group, no shuffle between them) into a single task at compile time. That chain runs as one Java thread inside the slot.

So a slot holds "one parallel instance of one chain." Events flow through the chain within the slot without network hops. Shuffle boundaries (`keyBy`, rebalance) break the chain — cross-slot network transfer at those points.

Not a whole operator (an operator has N parallel instances spread across N slots), not a single event (a task processes many events).

## 3. If a TM dies mid-checkpoint, what happens to the barriers already flowing through the DAG?

That checkpoint **declines** (fails). The JM's Checkpoint Coordinator marks it failed once it detects the missing TM (via heartbeat timeout). Barriers already flowing are dropped when the affected task fails.

Job then restarts per its restart strategy and rewinds to the *last successful* checkpoint. State changes between that last checkpoint and TM death are re-derived by replaying source records from the Kafka offsets stored in that last checkpoint. No data loss (assuming source is replayable) — records may be reprocessed once.

## 4. When would you deliberately disable operator chaining, given that chaining is more efficient?

- **Backpressure isolation** — chained operators share a thread; you can't tell which link in the chain is slow. Breaking the chain gives you per-operator backpressure indicators in the UI.
- **CPU-heavy operator** — one CPU-hungry operator in a chain slows the cheap operators. Break the chain to isolate.
- **Debugging / metrics granularity** — chain boundaries produce distinct operator vertices in the UI with their own metrics (numRecordsIn, numRecordsOut, latency).
- **Different parallelism needed** — chained operators must share parallelism. If you want operator A at parallelism 4 and operator B at 8, they can't chain.

Disable via `.startNewChain()` / `.disableChaining()` in the DataStream API, or set `pipeline.operator-chaining: false` globally.

## 5. Where does the JM get the "list of TMs and their slot capacity" — push (TMs register) or pull (JM discovers)?

**Push.** TMs discover the JM's address (`jobmanager.rpc.address` in the Flink config, injected by the operator via env / configmap) and *register* at TM startup by opening a connection to the JM's RPC endpoint. In the registration handshake TM reports its slot count and available resources.

JM maintains a slot pool and heartbeats to TMs periodically to keep the registration alive. If a TM's heartbeat times out, JM removes it from the slot pool and reschedules affected tasks per restart strategy.

Consequence: if a new TM Pod comes up (rescale), the JM sees it as soon as the TM's registration RPC completes — not on any polling interval.
