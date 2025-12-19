package com.example.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.function.Predicate;

class DataProcessorTest {

    private DataProcessor processor;

    private Predicate<String> mockFilter;

    private Function<String, Integer> mockTransformer;

    private Function<Integer, String> mockGrouper;

    private Function<String, Integer> mockAsyncProcessor;

    @BeforeEach
    void setUp() {
        processor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        if (processor != null) {
            processor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, and deduplicates with mocks")
    void testProcessDataPipeline_withMocks() {
        List<String> data = Arrays.asList("a", "b", "c", "null", "a");

        mockFilter = s -> true;
        mockTransformer = s -> {
            if ("null".equals(s)) return null;
            return s.length();
        };
        mockGrouper = v -> (v % 2 == 0) ? "even" : "odd";

        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                data,
                mockFilter,
                mockTransformer,
                mockGrouper,
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.containsKey("odd"));
        assertEquals(1, result.get("odd").size());
        assertEquals(1, result.get("odd").get(0));
        assertFalse(result.containsKey("even"));
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_emptyOrNull() {
        Map<String, List<Integer>> r1 = processor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                String::length,
                Object::toString,
                Comparator.naturalOrder()
        );
        assertNotNull(r1);
        assertTrue(r1.isEmpty());

        Map<String, List<Integer>> r2 = processor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                String::length,
                Object::toString,
                Comparator.naturalOrder()
        );
        assertNotNull(r2);
        assertTrue(r2.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: applies sorting and per-group limit 100 with distinct")
    void testProcessDataPipeline_limitAndSort() {
        List<Integer> data = new ArrayList<>();
        for (int i = 119; i >= 0; i--) {
            data.add(i);
        }

        Map<String, List<Integer>> result = processor.<Integer, Integer>processDataPipeline(
                data,
                i -> true,
                i -> i,
                i -> "G",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.containsKey("G"));
        List<Integer> group = result.get("G");
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev and detects outliers")
    void testCalculateStatistics_values() {
        List<Double> values = Arrays.asList(1.0, 2.0, 2.0, 3.0, 10.0);

        DataProcessor.StatisticalResult result = processor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(3.6, result.getMean(), 1e-9);
        assertEquals(2.0, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(3.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(10.64), result.getStandardDeviation(), 1e-9);

        List<Double> outliers = result.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(10.0, outliers.get(0), 1e-9);

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(5.0));
    }

    @Test
    @DisplayName("calculateStatistics: throws for null values list")
    void testCalculateStatistics_null() {
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws for empty values list")
    void testCalculateStatistics_empty() {
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes all keys and aggregates results")
    void testProcessInParallel_success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");

        mockAsyncProcessor = s -> s.length();

        CompletableFuture<Map<String, Integer>> future = processor.processInParallel(keys, mockAsyncProcessor);
        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a key processing fails")
    void testProcessInParallel_failure() {
        List<String> keys = Arrays.asList("good", "bad", "good2");

        mockAsyncProcessor = s -> {
            if ("bad".equals(s)) {
                throw new RuntimeException("boom");
            }
            return s.length();
        };

        CompletableFuture<Map<String, Integer>> future = processor.processInParallel(keys, mockAsyncProcessor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
        assertNotNull(ex.getCause().getCause());
        assertEquals("boom", ex.getCause().getCause().getMessage());
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances in a directed weighted graph")
    void testFindShortestPaths_success() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 4)));
        graph.put("B", new HashMap<>(Map.of("C", 2, "D", 5)));
        graph.put("C", new HashMap<>(Map.of("D", 1)));
        graph.put("D", new HashMap<>());

        Map<String, Integer> distances = processor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C"));
        assertEquals(4, distances.get("D"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_invalid() {
        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: terminates internal executor service")
    void testShutdown() throws Exception {
        assertFalse(isExecutorShutdown(processor));
        processor.shutdown();
        assertTrue(isExecutorShutdown(processor));
    }

    private boolean isExecutorShutdown(DataProcessor dp) throws Exception {
        Field f = DataProcessor.class.getDeclaredField("executorService");
        f.setAccessible(true);
        Object exec = f.get(dp);
        return exec instanceof java.util.concurrent.ExecutorService
                && ((java.util.concurrent.ExecutorService) exec).isShutdown();
    }
}