package com.company.flink.http;

import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Optional;

public record HttpResult(int statusCode, String body, Long retryAfterMillis) {
    public boolean isSuccess() {
        return statusCode >= 200 && statusCode < 300;
    }

    public static HttpResult from(HttpResponse<String> response) {
        return new HttpResult(
                response.statusCode(),
                response.body(),
                parseRetryAfter(response)
        );
    }

    private static Long parseRetryAfter(HttpResponse<?> response) {
        Optional<String> retryAfter = response.headers().firstValue("Retry-After");
        if (retryAfter.isEmpty()) {
            return null;
        }

        String value = retryAfter.get().trim();

        try {
            long seconds = Long.parseLong(value);
            return Duration.ofSeconds(seconds).toMillis();
        } catch (NumberFormatException ignored) {
            // Header can also be an HTTP-date.
        }

        try {
            ZonedDateTime dateTime = ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME);
            long millis = Duration.between(ZonedDateTime.now(), dateTime).toMillis();
            return Math.max(0L, millis);
        } catch (Exception ignored) {
            return null;
        }
    }
}
