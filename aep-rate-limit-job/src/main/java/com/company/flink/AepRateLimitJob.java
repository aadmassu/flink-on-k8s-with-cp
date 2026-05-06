package com.company.flink;

import com.company.flink.config.AppConfig;
import com.company.flink.functions.AepBatchingProcessFunction;
import com.company.flink.functions.AepHttpPostFunction;
import com.company.flink.functions.ValidateAndPrepareFunction;
import com.company.flink.model.AepBatch;
import com.company.flink.model.ErrorEvent;
import com.company.flink.model.RawKafkaRecord;
import com.company.flink.serialization.ErrorEventSerializationSchema;
import com.company.flink.serialization.RawKafkaRecordDeserializationSchema;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public final class AepRateLimitJob {
    private AepRateLimitJob() {
    }

    public static void main(String[] args) throws Exception {
        AppConfig config = AppConfig.fromEnv();

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(config.parallelism());

        if (config.checkpointingEnabled()) {
            env.enableCheckpointing(config.checkpointIntervalMs());
        }

        KafkaSource<RawKafkaRecord> source = KafkaSource.<RawKafkaRecord>builder()
                .setBootstrapServers(config.bootstrapServers())
                .setTopics(config.sourceTopics())
                .setGroupId(config.consumerGroupId())
                .setDeserializer(new RawKafkaRecordDeserializationSchema())
                .setProperties(config.kafkaConsumerProperties())
                .build();

        DataStream<RawKafkaRecord> kafkaRecords = env.fromSource(
                source,
                WatermarkStrategy.noWatermarks(),
                "kafka-post-smt-source"
        );

        SingleOutputStreamOperator<RawKafkaRecord> validRecords = kafkaRecords
                .process(new ValidateAndPrepareFunction())
                .name("validate-post-smt-records");

        DataStream<ErrorEvent> validationErrors = validRecords
                .getSideOutput(ValidateAndPrepareFunction.VALIDATION_DLQ_TAG);

        SingleOutputStreamOperator<AepBatch> batches = validRecords
                .keyBy(RawKafkaRecord::topicPartitionKey)
                .process(new AepBatchingProcessFunction(config))
                .name("batch-records-for-aep");

        DataStream<ErrorEvent> httpErrors = batches
                .flatMap(new AepHttpPostFunction(config))
                .name("rate-limited-aep-http-post");

        KafkaSink<ErrorEvent> dlqSink = KafkaSink.<ErrorEvent>builder()
                .setBootstrapServers(config.bootstrapServers())
                .setKafkaProducerConfig(config.kafkaProducerProperties())
                .setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                .setRecordSerializer(
                        KafkaRecordSerializationSchema.builder()
                                .setTopic(config.dlqTopic())
                                .setValueSerializationSchema(new ErrorEventSerializationSchema())
                                .build()
                )
                .build();

        validationErrors.sinkTo(dlqSink).name("validation-dlq-sink");
        httpErrors.sinkTo(dlqSink).name("aep-http-dlq-sink");

        env.execute(config.jobName());
    }
}
