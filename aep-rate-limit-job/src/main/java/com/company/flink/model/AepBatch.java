package com.company.flink.model;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

public class AepBatch implements Serializable {
    private List<RawKafkaRecord> records = new ArrayList<>();
    private int totalPayloadBytes;
    private long createdAtEpochMs;

    public AepBatch() {
        this.createdAtEpochMs = System.currentTimeMillis();
    }

    public AepBatch(List<RawKafkaRecord> records, int totalPayloadBytes) {
        this.records = new ArrayList<>(records);
        this.totalPayloadBytes = totalPayloadBytes;
        this.createdAtEpochMs = System.currentTimeMillis();
    }

    public List<RawKafkaRecord> getRecords() {
        return records;
    }

    public int getTotalPayloadBytes() {
        return totalPayloadBytes;
    }

    public long getCreatedAtEpochMs() {
        return createdAtEpochMs;
    }

    public int size() {
        return records == null ? 0 : records.size();
    }

    public boolean isEmpty() {
        return size() == 0;
    }

    public String firstSourceTopic() {
        return isEmpty() ? null : records.get(0).getTopic();
    }

    public int firstSourcePartition() {
        return isEmpty() ? -1 : records.get(0).getPartition();
    }

    public long firstSourceOffset() {
        return isEmpty() ? -1L : records.get(0).getOffset();
    }

    public long lastSourceOffset() {
        return isEmpty() ? -1L : records.get(records.size() - 1).getOffset();
    }
}
