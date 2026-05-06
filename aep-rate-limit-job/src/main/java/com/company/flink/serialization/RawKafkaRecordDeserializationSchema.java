package com.company.flink.serialization;

import com.company.flink.model.RawKafkaRecord;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.connector.kafka.source.reader.deserializer.KafkaRecordDeserializationSchema;
import org.apache.flink.util.Collector;
import org.apache.kafka.clients.consumer.ConsumerRecord;

import java.io.IOException;

public class RawKafkaRecordDeserializationSchema implements KafkaRecordDeserializationSchema<RawKafkaRecord> {
    @Override
    public void deserialize(ConsumerRecord<byte[], byte[]> record, Collector<RawKafkaRecord> out) throws IOException {
        out.collect(new RawKafkaRecord(
                record.topic(),
                record.partition(),
                record.offset(),
                record.timestamp(),
                record.key(),
                record.value()
        ));
    }

    @Override
    public TypeInformation<RawKafkaRecord> getProducedType() {
        return TypeInformation.of(RawKafkaRecord.class);
    }
}
