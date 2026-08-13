#!/bin/bash
# Kafka broker resource utilization check.
# Run these one at a time on a Kafka broker VM.
# Bootstrap port assumed 9094 (FCB PLAINTEXT listener); adjust if different.
# Log dir assumed /var/lib/kafka/data; replace with the actual log.dirs value.

# --- Host: CPU / memory / disk ---

# Kernel and OS release info
uname -a

# Uptime plus 1 / 5 / 15 minute load averages
uptime

# Number of logical CPU cores (compare against load average)
nproc

# Total / used / free / cached memory and swap, human-readable
free -h

# Per-mount disk usage, human-readable (watch the partition holding log.dirs)
df -h

# Snapshot of top 25 processes ordered by CPU
top -bn1 | head -25

# --- Kafka JVM process ---

# Kafka broker PID and full command line (heap, GC flags, log.dirs, JMX flags)
ps -ef | grep -E "kafka\.Kafka" | grep -v grep

# Kafka JVM resident size (RSS), virtual size, CPU%, MEM%, elapsed time
ps -o pid,user,vsz,rss,pcpu,pmem,etime,cmd -p $(pgrep -f "kafka\.Kafka" | head -1)

# Number of file descriptors currently open by the Kafka JVM
ls /proc/$(pgrep -f "kafka\.Kafka" | head -1)/fd 2>/dev/null | wc -l

# Kafka JVM file-descriptor limit (compare against the open count above)
grep "Max open files" /proc/$(pgrep -f "kafka\.Kafka" | head -1)/limits

# JVM heap usage by region (Eden, Survivor, Old, Metaspace) and cumulative GC stats
jstat -gc $(pgrep -f "kafka\.Kafka" | head -1)

# JVM heap committed vs used vs max
jcmd $(pgrep -f "kafka\.Kafka" | head -1) GC.heap_info

# --- Kafka log directories / disk usage ---

# Confirm the log.dirs path the broker is using
grep "^log.dirs" /etc/kafka/server.properties

# Total size of the Kafka log directory (adjust path as needed)
du -sh /var/lib/kafka/data

# Top 20 largest topic-partition directories under the log dir
du -sh /var/lib/kafka/data/*/ 2>/dev/null | sort -h | tail -20

# Block-device I/O stats, two 1-second samples (look at the device backing log.dirs)
iostat -xz 1 2

# --- Kafka cluster state via CLI ---

# Confirm the broker is up and serving the client listener
kafka-broker-api-versions --bootstrap-server localhost:9094 | head -5

# Total topic count cluster-wide
kafka-topics --bootstrap-server localhost:9094 --list | wc -l

# Under-replicated partitions (empty output = healthy)
kafka-topics --bootstrap-server localhost:9094 --describe --under-replicated-partitions

# Partitions with no leader (any output is urgent)
kafka-topics --bootstrap-server localhost:9094 --describe --unavailable-partitions

# Per-broker log-dir sizes (replace 1 with this broker's broker.id)
kafka-log-dirs --bootstrap-server localhost:9094 --describe --broker-list 1

# Total consumer-group count
kafka-consumer-groups --bootstrap-server localhost:9094 --list | wc -l

# Dynamic broker config overrides (anything not at default)
kafka-configs --bootstrap-server localhost:9094 --entity-type brokers --describe

# --- Network ---

# Established TCP connections on the Kafka client port
ss -tn state established '( sport = :9094 )' | wc -l

# Top 10 remote client IPs by connection count on the client port
ss -tn state established '( sport = :9094 )' | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10

# Listening sockets owned by the Kafka JVM
ss -tlnp 2>/dev/null | grep $(pgrep -f "kafka\.Kafka" | head -1)
