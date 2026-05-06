package com.company.flink.functions;

import com.company.flink.model.RawKafkaRecord;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.functions.OpenContext;  
import org.apache.flink.streaming.api.functions.ProcessFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.util.OutputTag;
import com.company.flink.model.ErrorEvent;

public class ValidateAndPrepareFunction extends ProcessFunction<RawKafkaRecord, RawKafkaRecord> {
    public static final OutputTag<ErrorEvent> VALIDATION_DLQ_TAG = new OutputTag<>("validation-dlq") {};
    private transient ObjectMapper objectMapper;

    @Override
   public void open(OpenContext openContext) {          // replace Configuration parameter
    this.objectMapper = new ObjectMapper();
}

    @Override
    public void processElement(RawKafkaRecord record, Context ctx, Collector<RawKafkaRecord> out) {
        if (record == null) {
            return;
        }

        // Debezium tombstones are null values. AEP does not need tombstones for this POC.
        if (record.getValue() == null || record.getValue().length == 0) {
            return;
        }

        try {
            objectMapper.readTree(record.getValue());
            out.collect(record);
        } catch (Exception e) {
            ctx.output(
                    VALIDATION_DLQ_TAG,
                    ErrorEvent.validation(record, "Kafka value is not parseable JSON", e)
            );
        }
    }
}
