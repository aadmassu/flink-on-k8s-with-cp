package com.company.flink.config;

import java.io.Serializable;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;

public record AppConfig(
        String jobName,
        String bootstrapServers,
        List<String> sourceTopics,
        String dlqTopic,
        String consumerGroupId,
        String autoOffsetReset,
        int parallelism,
        boolean checkpointingEnabled,
        long checkpointIntervalMs,

        String aepEndpointUrl,
        String contentType,
        String aepBatchMode,
        int rateLimitRequestsPerSecond,
        int targetBatchSizeBytes,
        int maxBatchSizeBytes,
        int maxBatchRecords,
        long batchFlushIntervalMs,
        int httpTimeoutMs,
        int httpMaxRetries,
        long httpInitialBackoffMs,
        long httpMaxBackoffMs,
        boolean enableDynamic429Backoff,
        boolean enableDownstreamCompression
) implements Serializable {

    public static AppConfig fromEnv() {
        return new AppConfig(
                env("JOB_NAME", "aep-rate-limit-job"),
                required("BOOTSTRAP_SERVERS"),
                csv(required("SOURCE_TOPICS")),
                required("DLQ_TOPIC"),
                env("CONSUMER_GROUP_ID", "aep-rate-limit-group"),
                env("AUTO_OFFSET_RESET", "earliest"),
                integer("PARALLELISM", 2),
                bool("CHECKPOINTING_ENABLED", true),
                lng("CHECKPOINT_INTERVAL_MS", 60_000L),

                required("AEP_ENDPOINT_URL"),
                env("CONTENT_TYPE", "application/json"),
                env("AEP_BATCH_MODE", "JSON_ARRAY"),
                integer("RATE_LIMIT_REQUESTS_PER_SECOND", 200),
                integer("TARGET_BATCH_SIZE_BYTES", 10 * 1024),
                integer("MAX_BATCH_SIZE_BYTES", 50 * 1024),
                integer("MAX_BATCH_RECORDS", 166),
                lng("BATCH_FLUSH_INTERVAL_MS", 100L),
                integer("HTTP_TIMEOUT_MS", 10_000),
                integer("HTTP_MAX_RETRIES", 6),
                lng("HTTP_INITIAL_BACKOFF_MS", 500L),
                lng("HTTP_MAX_BACKOFF_MS", 30_000L),
                bool("ENABLE_DYNAMIC_429_BACKOFF", true),
                bool("ENABLE_DOWNSTREAM_COMPRESSION", false)
        );
    }

    public Properties kafkaConsumerProperties() {
        Properties props = commonKafkaProperties();
        props.setProperty("auto.offset.reset", autoOffsetReset);
        props.setProperty("enable.auto.commit", "false");
        putIfPresent(props, "isolation.level", "KAFKA_ISOLATION_LEVEL");
        return props;
    }

    public Properties kafkaProducerProperties() {
        Properties props = commonKafkaProperties();
        props.setProperty("acks", env("KAFKA_PRODUCER_ACKS", "all"));
        props.setProperty("enable.idempotence", env("KAFKA_PRODUCER_ENABLE_IDEMPOTENCE", "true"));
        return props;
    }

    public static Properties commonKafkaProperties() {
        Properties props = new Properties();
        putIfPresent(props, "security.protocol", "SECURITY_PROTOCOL");
        putIfPresent(props, "sasl.mechanism", "SASL_MECHANISM");
        putIfPresent(props, "sasl.jaas.config", "SASL_JAAS_CONFIG");
        putIfPresent(props, "ssl.truststore.location", "SSL_TRUSTSTORE_LOCATION");
        putIfPresent(props, "ssl.truststore.password", "SSL_TRUSTSTORE_PASSWORD");
        putIfPresent(props, "ssl.keystore.location", "SSL_KEYSTORE_LOCATION");
        putIfPresent(props, "ssl.keystore.password", "SSL_KEYSTORE_PASSWORD");
        putIfPresent(props, "ssl.key.password", "SSL_KEY_PASSWORD");
        return props;
    }

    public static String env(String key, String defaultValue) {
        String value = System.getenv(key);
        return value == null || value.isBlank() ? defaultValue : value.trim();
    }

    public static String optional(String key) {
        String value = System.getenv(key);
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static String required(String key) {
        String value = optional(key);
        if (value == null) {
            throw new IllegalArgumentException("Missing required environment variable: " + key);
        }
        return value;
    }

    private static List<String> csv(String csv) {
        return Arrays.stream(csv.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
    }

    private static int integer(String key, int defaultValue) {
        return Integer.parseInt(env(key, String.valueOf(defaultValue)));
    }

    private static long lng(String key, long defaultValue) {
        return Long.parseLong(env(key, String.valueOf(defaultValue)));
    }

    private static boolean bool(String key, boolean defaultValue) {
        return Boolean.parseBoolean(env(key, String.valueOf(defaultValue)));
    }

    private static void putIfPresent(Properties props, String kafkaKey, String envKey) {
        String value = optional(envKey);
        if (value != null) {
            props.setProperty(kafkaKey, value);
        }
    }
}
