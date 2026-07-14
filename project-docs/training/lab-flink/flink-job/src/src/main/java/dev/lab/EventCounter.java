package dev.lab;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.RichMapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.utils.ParameterTool;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

/**
 * Per-user event counter for the training lab.
 *
 * Reads plain-text lines "userId|action|timestamp" from events-in, keys by userId,
 * maintains a per-key ValueState<Long> running count, emits "userId=N" strings
 * to counts-out on every event.
 *
 * Concept-by-concept map:
 *   - Source connector       -> Week 5 Mon (sources)
 *   - keyBy(userId)          -> Week 5 Mon (partitioning), Week 6 Mon (DataStream API)
 *   - ValueState<Long>       -> Week 5 Mon (stateful streaming), Week 6 Wed (state)
 *   - Kafka sink at-least-once -> Week 6 Thu (delivery guarantees)
 *
 * Deliberately no windows / no watermarks: keeps the DAG shape minimal and
 * focused on the state primitive.
 */
public class EventCounter {

    public static void main(String[] args) throws Exception {
        ParameterTool params = ParameterTool.fromArgs(args);
        String bootstrap = params.getRequired("kafka.bootstrap");
        String sourceTopic = params.get("source.topic", "events-in");
        String sinkTopic = params.get("sink.topic", "counts-out");

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        KafkaSource<String> source = KafkaSource.<String>builder()
                .setBootstrapServers(bootstrap)
                .setTopics(sourceTopic)
                .setGroupId("event-counter")
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();

        DataStream<String> raw = env.fromSource(source, WatermarkStrategy.noWatermarks(), "events-in");

        DataStream<String> counts = raw
                .map(line -> line.split("\\|", 3)[0]).returns(Types.STRING).name("extract-userId")
                .keyBy(userId -> userId)
                .map(new PerKeyCounter()).name("count-per-user");

        KafkaSink<String> sink = KafkaSink.<String>builder()
                .setBootstrapServers(bootstrap)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic(sinkTopic)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build())
                .setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                .build();

        counts.sinkTo(sink).name("counts-out");

        env.execute("event-counter");
    }

    // Keyed state carrier — one Long per userId, checkpointed by Flink.
    public static class PerKeyCounter extends RichMapFunction<String, String> {
        private transient ValueState<Long> countState;

        @Override
        public void open(Configuration parameters) {
            countState = getRuntimeContext().getState(
                    new ValueStateDescriptor<>("event-count", Types.LONG));
        }

        @Override
        public String map(String userId) throws Exception {
            Long current = countState.value();
            long next = (current == null ? 0L : current) + 1L;
            countState.update(next);
            return userId + "=" + next;
        }
    }
}
