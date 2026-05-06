package com.company.flink.http;

import com.company.flink.config.AppConfig;
import com.company.flink.model.AepBatch;
import com.company.flink.model.RawKafkaRecord;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

public class AepHttpClient {
    private final AppConfig config;
    private final HttpClient client;

    public AepHttpClient(AppConfig config) {
        this.config = config;
        this.client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(config.httpTimeoutMs()))
                .build();
    }

    public HttpResult postBatch(AepBatch batch) throws IOException, InterruptedException {
        String body = buildBody(batch);
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(config.aepEndpointUrl()))
                .timeout(Duration.ofMillis(config.httpTimeoutMs()))
                .header("Content-Type", config.contentType())
                .header("Accept", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));

        // AEP auth/header values are optional and externally configured via K8s Secret.
        addHeaderIfPresent(builder, "AEP_AUTH_HEADER_NAME", "AEP_AUTH_HEADER_VALUE");
        addHeaderIfPresent(builder, "AEP_HEADER_1_NAME", "AEP_HEADER_1_VALUE");
        addHeaderIfPresent(builder, "AEP_HEADER_2_NAME", "AEP_HEADER_2_VALUE");
        addHeaderIfPresent(builder, "AEP_HEADER_3_NAME", "AEP_HEADER_3_VALUE");
        addHeaderIfPresent(builder, "AEP_HEADER_4_NAME", "AEP_HEADER_4_VALUE");
        addHeaderIfPresent(builder, "AEP_HEADER_5_NAME", "AEP_HEADER_5_VALUE");

        String apiKey = AppConfig.optional("AEP_API_KEY");
        if (apiKey != null && AppConfig.optional("AEP_HEADER_1_NAME") == null) {
            builder.header("x-api-key", apiKey);
        }

        String clientSecret = AppConfig.optional("AEP_CLIENT_SECRET");
        if (clientSecret != null) {
            builder.header("x-client-secret", clientSecret);
        }

        if (!config.enableDownstreamCompression()) {
            builder.header("Content-Encoding", "identity");
        }

        HttpResponse<String> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        return HttpResult.from(response);
    }

    private String buildBody(AepBatch batch) {
        String mode = config.aepBatchMode().toUpperCase();
        List<String> values = new ArrayList<>(batch.size());

        for (RawKafkaRecord record : batch.getRecords()) {
            values.add(record.valueAsString());
        }

        return switch (mode) {
            case "NDJSON" -> String.join("\n", values);
            case "SINGLE_RECORD" -> values.get(0);
            case "JSON_ARRAY" -> "[" + String.join(",", values) + "]";
            default -> throw new IllegalArgumentException("Unsupported AEP_BATCH_MODE: " + config.aepBatchMode());
        };
    }

    private static void addHeaderIfPresent(HttpRequest.Builder builder, String nameEnv, String valueEnv) {
        String name = AppConfig.optional(nameEnv);
        String value = AppConfig.optional(valueEnv);
        if (name != null && value != null) {
            builder.header(name, value);
        }
    }
}
