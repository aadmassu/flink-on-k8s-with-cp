package com.company.flink.ratelimit;

import java.io.Serializable;

public class TokenBucketRateLimiter implements Serializable {
    private final double refillTokensPerSecond;
    private final double capacity;

    private double availableTokens;
    private long lastRefillNanos;

    public TokenBucketRateLimiter(double refillTokensPerSecond, double capacity) {
        if (refillTokensPerSecond <= 0) {
            throw new IllegalArgumentException("refillTokensPerSecond must be positive");
        }
        this.refillTokensPerSecond = refillTokensPerSecond;
        this.capacity = Math.max(1.0d, capacity);
        this.availableTokens = this.capacity;
        this.lastRefillNanos = System.nanoTime();
    }

    public synchronized void acquire() {
        while (true) {
            refill();

            if (availableTokens >= 1.0d) {
                availableTokens -= 1.0d;
                return;
            }

            double missingTokens = 1.0d - availableTokens;
            long sleepNanos = (long) ((missingTokens / refillTokensPerSecond) * 1_000_000_000L);
            long sleepMillis = Math.max(1L, sleepNanos / 1_000_000L);

            try {
                wait(sleepMillis);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Interrupted while waiting for rate-limit token", e);
            }
        }
    }

    private void refill() {
        long now = System.nanoTime();
        long elapsedNanos = now - lastRefillNanos;
        if (elapsedNanos <= 0) {
            return;
        }

        double tokensToAdd = (elapsedNanos / 1_000_000_000.0d) * refillTokensPerSecond;
        availableTokens = Math.min(capacity, availableTokens + tokensToAdd);
        lastRefillNanos = now;
    }
}
