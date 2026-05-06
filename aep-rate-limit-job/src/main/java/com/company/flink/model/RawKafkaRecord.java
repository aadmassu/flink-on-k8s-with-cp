package com.company.flink.model;

import java.io.Serializable;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class RawKafkaRecord implements Serializable {
    private String topic;
    private int partition;
    private long offset;
    private long timestamp;
    private byte[] key;
    private byte[] value;

    public RawKafkaRecord() {
    }

    public RawKafkaRecord(String topic, int partition, long offset, long timestamp, byte[] key, byte[] value) {
        this.topic = topic;
        this.partition = partition;
        this.offset = offset;
        this.timestamp = timestamp;
        this.key = key == null ? null : Arrays.copyOf(key, key.length);
        this.value = value == null ? null : Arrays.copyOf(value, value.length);
    }

    public String topicPartitionKey() {
        return topic + "-" + partition;
    }

    public String keyAsString() {
        return key == null ? null : new String(key, StandardCharsets.UTF_8);
    }

    public String valueAsString() {
        return value == null ? null : new String(value, StandardCharsets.UTF_8);
    }

    public int valueSizeBytes() {
        return value == null ? 0 : value.length;
    }

    public String getTopic() {
        return topic;
    }

    public int getPartition() {
        return partition;
    }

    public long getOffset() {
        return offset;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public byte[] getKey() {
        return key;
    }

    public byte[] getValue() {
        return value;
    }

    public void setTopic(String topic) {
        this.topic = topic;
    }

    public void setPartition(int partition) {
        this.partition = partition;
    }

    public void setOffset(long offset) {
        this.offset = offset;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public void setKey(byte[] key) {
        this.key = key;
    }

    public void setValue(byte[] value) {
        this.value = value;
    }
}
