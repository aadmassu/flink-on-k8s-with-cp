package com.company.flink.ratelimit;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class TokenBucketRateLimiterTest {
    @Test
    void acquireEventuallyReturns() {
        TokenBucketRateLimiter limiter = new TokenBucketRateLimiter(10.0d, 1.0d);
        limiter.acquire();
        long start = System.currentTimeMillis();
        limiter.acquire();
        long elapsed = System.currentTimeMillis() - start;
        assertTrue(elapsed >= 50, "second acquire should wait at least briefly");
    }
}
