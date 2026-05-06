package com.company.flink.model;

import java.io.Serializable;
import java.time.Instant;

public class ErrorEvent implements Serializable {
    private String failureStage;
    private String errorClass;
    private String errorMessage;
    private Integer httpStatus;
    private String httpResponseBody;
    private Integer attemptCount;
    private String sourceTopic;
    private Integer sourcePartition;
    private Long sourceOffset;
    private Long sourceTimestamp;
    private String recordKey;
    private String originalPayload;
    private String errorTimestamp;

    public ErrorEvent() {
    }

    public static ErrorEvent validation(RawKafkaRecord record, String reason, Exception exception) {
        ErrorEvent event = fromRecord(record);
        event.failureStage = "validate";
        event.errorClass = exception == null ? "ValidationError" : exception.getClass().getName();
        event.errorMessage = reason;
        event.errorTimestamp = Instant.now().toString();
        return event;
    }

    public static ErrorEvent http(AepBatch batch, int status, String responseBody, int attempts, String message) {
        ErrorEvent event = fromBatch(batch);
        event.failureStage = "aep-http-sink";
        event.errorClass = "HttpError";
        event.errorMessage = message;
        event.httpStatus = status;
        event.httpResponseBody = responseBody;
        event.attemptCount = attempts;
        event.errorTimestamp = Instant.now().toString();
        return event;
    }

    public static ErrorEvent exception(AepBatch batch, Exception exception, int attempts) {
        ErrorEvent event = fromBatch(batch);
        event.failureStage = "aep-http-sink";
        event.errorClass = exception == null ? "Exception" : exception.getClass().getName();
        event.errorMessage = exception == null ? null : exception.getMessage();
        event.attemptCount = attempts;
        event.errorTimestamp = Instant.now().toString();
        return event;
    }

    private static ErrorEvent fromRecord(RawKafkaRecord record) {
        ErrorEvent event = new ErrorEvent();
        if (record != null) {
            event.sourceTopic = record.getTopic();
            event.sourcePartition = record.getPartition();
            event.sourceOffset = record.getOffset();
            event.sourceTimestamp = record.getTimestamp();
            event.recordKey = record.keyAsString();
            event.originalPayload = record.valueAsString();
        }
        return event;
    }

    private static ErrorEvent fromBatch(AepBatch batch) {
        ErrorEvent event = new ErrorEvent();
        if (batch != null && !batch.isEmpty()) {
            RawKafkaRecord first = batch.getRecords().get(0);
            event.sourceTopic = first.getTopic();
            event.sourcePartition = first.getPartition();
            event.sourceOffset = first.getOffset();
            event.sourceTimestamp = first.getTimestamp();
            event.recordKey = first.keyAsString();
            event.originalPayload = "batch_size=" + batch.size()
                    + ", totalPayloadBytes=" + batch.getTotalPayloadBytes()
                    + ", firstOffset=" + batch.firstSourceOffset()
                    + ", lastOffset=" + batch.lastSourceOffset();
        }
        return event;
    }

    public String getFailureStage() {
        return failureStage;
    }

    public String getErrorClass() {
        return errorClass;
    }

    public String getErrorMessage() {
        return errorMessage;
    }

    public Integer getHttpStatus() {
        return httpStatus;
    }

    public String getHttpResponseBody() {
        return httpResponseBody;
    }

    public Integer getAttemptCount() {
        return attemptCount;
    }

    public String getSourceTopic() {
        return sourceTopic;
    }

    public Integer getSourcePartition() {
        return sourcePartition;
    }

    public Long getSourceOffset() {
        return sourceOffset;
    }

    public Long getSourceTimestamp() {
        return sourceTimestamp;
    }

    public String getRecordKey() {
        return recordKey;
    }

    public String getOriginalPayload() {
        return originalPayload;
    }

    public String getErrorTimestamp() {
        return errorTimestamp;
    }
}
