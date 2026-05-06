package com.company.flink.serialization;

import com.company.flink.model.ErrorEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.serialization.SerializationSchema;

public class ErrorEventSerializationSchema implements SerializationSchema<ErrorEvent> {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Override
    public byte[] serialize(ErrorEvent element) {
        try {
            return MAPPER.writeValueAsBytes(element);
        } catch (Exception e) {
            throw new RuntimeException("Failed to serialize DLQ ErrorEvent", e);
        }
    }
}
