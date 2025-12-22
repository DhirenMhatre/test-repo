package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DataProcessor Tests")
class DataProcessorTest {

    private DataProcessor dataProcessor;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
        dataProcessor = null;
    }

    // Constructor

    @Test
    @DisplayName("Should create instance successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    // processDataPipeline

    @Test
    @DisplayName("processDataPipeline: returns empty map when data is null")
    void testProcessDataPipeline_NullData() {
        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        null,
                        s -> true,
                        s -> s,
                        s -> "any",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when data is empty")
    void testProcessDataPipeline_EmptyData() {
        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        new java.util.ArrayList<>(),
                        s -> true,
                        s -> s,
                        s -> "any",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, and deduplicates")
    void testProcessDataPipeline_CoreFunctionality() {
        java.util.List<String> data = java.util.Arrays.asList(
                "apple", "apricot", "banana", "banana", "avocado", "blueberry", ""
        );

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        s -> s != null && !s.isEmpty(),
                        s -> s.isEmpty() ? null : s.toUpperCase(),
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(2, result.size());

        assertTrue(result.containsKey("A"));
        assertTrue(result.containsKey("B"));

        java.util.List<String> groupA = result.get("A");
        java.util.List<String> groupB = result.get("B");

        assertIterableEquals(java.util.Arrays.asList("APPLE", "APRICOT", "AVOCADO"), groupA);
        assertIterableEquals(java.util.Arrays.asList("BANANA", "BLUEBERRY"), groupB);
    }

    @Test
    @DisplayName("processDataPipeline: limits to 100 items per group after deduplication")
    void testProcessDataPipeline_LimitPerGroup() {
        java.util.List<Integer> data = new java.util.ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }

        java.util.Map<String, java.util.List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        data,
                        n -> true,
                        n -> n, // identity
                        n -> "G",
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        java.util.List<Integer> group = result.get("G");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
    }

    // calculateStatistics

    @Test
    @DisplayName("calculateStatistics: throws for null input")
    void testCalculateStatistics_Null() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws for empty input")
    void testCalculateStatistics_Empty() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(new java.util.ArrayList<>()));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev with no outliers")
    void testCalculateStatistics_Basic() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(3.0, result.getMean(), 0.0001);
        assertEquals(3.0, result.getMedian(), 0.0001);
        // Percentiles per implementation: index = ceil(p/100 * n) - 1
        assertEquals(2.0, result.getQ1(), 0.0001);
        assertEquals(4.0, result.getQ3(), 0.0001);

        // Population std dev
        assertEquals(Math.sqrt(2.0), result.getStandardDeviation(), 0.0001);

        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: detects outliers and computes stddev correctly")
    void testCalculateStatistics_Outliers() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 14.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(4.4, result.getMean(), 0.0001);
        assertEquals(2.0, result.getQ1(), 0.0001);
        assertEquals(3.0, result.getQ3(), 0.0001);

        // std dev = sqrt(23.44) ≈ 4.841487
        assertEquals(Math.sqrt(23.44), result.getStandardDeviation(), 0.0001);

        assertNotNull(result.getOutliers());
        assertEquals(1, result.getOutliers().size());
        assertEquals(14.0, result.getOutliers().get(0), 0.0001);
    }

    @Test
    @DisplayName("calculateStatistics: constant values yield zero stddev and no outliers")
    void testCalculateStatistics_ConstantValues() {
        java.util.List<Double> values = java.util.Arrays.asList(5.0, 5.0, 5.0, 5.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(5.0, result.getMean(), 0.0001);
        assertEquals(5.0, result.getMedian(), 0.0001);
        assertEquals(5.0, result.getQ1(), 0.0001);
        assertEquals(5.0, result.getQ3(), 0.0001);
        assertEquals(0.0, result.getStandardDeviation(), 0.0001);
        assertTrue(result.getOutliers().isEmpty());
    }

    // processInParallel

    @Test
    @DisplayName("processInParallel: completes successfully and returns expected map")
    void testProcessInParallel_Success() {
        java.util.List<String> keys = java.util.Arrays.asList("x", "y", "zz");

        java.util.concurrent.CompletableFuture<java.util.Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, String::length);

        java.util.Map<String, Integer> result = future.join();
        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("x"));
        assertEquals(1, result.get("y"));
        assertEquals(2, result.get("zz"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep the first computed value")
    void testProcessInParallel_DuplicateKeysKeepsFirst() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "b", "a");
        java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.atomic.AtomicInteger> counters =
                new java.util.concurrent.ConcurrentHashMap<>();

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, key -> {
                    java.util.concurrent.atomic.AtomicInteger counter =
                            counters.computeIfAbsent(key, k -> new java.util.concurrent.atomic.AtomicInteger(0));
                    int c = counter.getAndIncrement();
                    // distinguish first and second invocation for the same key
                    return key + "-" + c;
                });

        java.util.Map<String, String> result = future.join();
        assertNotNull(result);
        // Distinct keys only
        assertEquals(2, result.size());
        assertEquals("a-0", result.get("a")); // first value kept
        assertTrue(result.get("b").startsWith("b-"));
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when one task fails")
    void testProcessInParallel_Exception() {
        java.util.List<String> keys = java.util.Arrays.asList("ok1", "bad", "ok2");

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, key -> {
                    if ("bad".equals(key)) {
                        throw new RuntimeException("boom");
                    }
                    return key.toUpperCase();
                });

        assertThrows(java.util.concurrent.CompletionException.class, future::join);
    }

    // findShortestPaths

    @Test
    @DisplayName("findShortestPaths: computes correct shortest distances including unreachable nodes")
    void testFindShortestPaths_BasicAndDisconnected() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();

        java.util.Map<String, Integer> edgesA = new java.util.HashMap<>();
        edgesA.put("B", 1);
        edgesA.put("C", 4);

        java.util.Map<String, Integer> edgesB = new java.util.HashMap<>();
        edgesB.put("C", 2);
        edgesB.put("D", 5);

        java.util.Map<String, Integer> edgesC = new java.util.HashMap<>();
        edgesC.put("D", 1);

        // Disconnected node E
        java.util.Map<String, Integer> edgesD = new java.util.HashMap<>();
        java.util.Map<String, Integer> edgesE = new java.util.HashMap<>();

        graph.put("A", edgesA);
        graph.put("B", edgesB);
        graph.put("C", edgesC);
        graph.put("D", edgesD);
        graph.put("E", edgesE);

        java.util.Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");
        assertNotNull(distances);
        assertEquals(5, distances.size());

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        // A->B->C cost = 1+2=3 is shorter than A->C=4
        assertEquals(3, distances.get("C").intValue());
        // A->B->C->D = 1+2+1 = 4
        assertEquals(4, distances.get("D").intValue());
        // Disconnected E remains Integer.MAX_VALUE
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue());
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph")
    void testFindShortestPaths_NullGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: throws when start node not in graph")
    void testFindShortestPaths_InvalidStartNode() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("X", new java.util.HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}