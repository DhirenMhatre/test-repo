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
            dataProcessor = null;
        }
    }

    @Test
    @DisplayName("Should create instance successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics: even count with outlier - computes mean, median, quartiles, std dev, outliers")
    void testCalculateStatistics_EvenCount_WithOutlier() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(18.6666667, result.getMean(), 1e-6);
        assertEquals(2.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(4.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(1322.6111111), result.getStandardDeviation(), 1e-6);

        java.util.List<Double> outliers = result.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: odd count without outliers - correct central tendency and dispersion")
    void testCalculateStatistics_OddCount_NoOutliers() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 3.0, 5.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(3.0, result.getMean(), 1e-9);
        assertEquals(3.0, result.getMedian(), 1e-9);
        assertEquals(1.0, result.getQ1(), 1e-9);
        assertEquals(5.0, result.getQ3(), 1e-9);

        double expectedStdDev = Math.sqrt((4.0 + 0.0 + 4.0) / 3.0);
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-9);

        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: throws for null or empty input")
    void testCalculateStatistics_ThrowsForNullOrEmpty() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(java.util.Collections.emptyList()));
    }

    @Test
    @DisplayName("calculateStatistics: outliers list is unmodifiable")
    void testStatisticalResult_OutliersListIsUnmodifiable() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        assertThrows(UnsupportedOperationException.class, () -> result.getOutliers().add(5.0));
    }

    // processDataPipeline tests

    @Test
    @DisplayName("processDataPipeline: null and empty input return empty map")
    void testProcessDataPipeline_NullOrEmpty_ReturnsEmptyMap() {
        java.util.Map<String, java.util.List<String>> resultNull =
                dataProcessor.<String, String>processDataPipeline(null, s -> true, s -> s, s -> s, java.util.Comparator.naturalOrder());
        java.util.Map<String, java.util.List<String>> resultEmpty =
                dataProcessor.<String, String>processDataPipeline(java.util.Collections.emptyList(), s -> true, s -> s, s -> s, java.util.Comparator.naturalOrder());

        assertTrue(resultNull.isEmpty());
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filters, maps to uppercase, sorts, groups by first letter, dedupes within group")
    void testProcessDataPipeline_FilterMapSortGroupDedup() {
        java.util.List<String> data = java.util.Arrays.asList(
                "apple", "apricot", "banana", "banana", "blueberry", "avocado", "blackberry", "apricot"
        );

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        s -> s != null && (s.startsWith("a") || s.startsWith("b")),
                        s -> "banana".equals(s) ? null : s.toUpperCase(), // map some to null to test null filtering
                        s -> s.substring(0, 1), // group by first letter
                        java.util.Comparator.naturalOrder()
                );

        assertEquals(2, result.size());

        java.util.List<String> groupA = result.get("A");
        java.util.List<String> groupB = result.get("B");

        assertNotNull(groupA);
        assertNotNull(groupB);

        // A group: APPLE, APRICOT, AVOCADO (in sorted order)
        assertEquals(java.util.Arrays.asList("APPLE", "APRICOT", "AVOCADO"), groupA);

        // B group: BANANA was mapped to null and dropped; BLACKBERRY, BLUEBERRY remain (in sorted order)
        assertEquals(java.util.Arrays.asList("BLACKBERRY", "BLUEBERRY"), groupB);

        // Ensure duplicates of APRICOT were deduplicated
        assertEquals(3, groupA.size());
    }

    @Test
    @DisplayName("processDataPipeline: enforces limit of 100 items per group after dedup")
    void testProcessDataPipeline_LimitPerGroup() {
        java.util.List<Integer> data = new java.util.ArrayList<>();
        for (int i = 0; i < 150; i++) data.add(i); // 150 distinct items

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<Integer, String>processDataPipeline(
                        data,
                        i -> true,
                        i -> "A" + String.format("%03d", i), // all belong to group "A"
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertEquals(1, result.size());
        java.util.List<String> groupA = result.get("A");
        assertNotNull(groupA);
        assertEquals(100, groupA.size());
        assertEquals("A000", groupA.get(0));
        assertEquals("A099", groupA.get(99));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel: successful execution aggregates results by key")
    void testProcessInParallel_Success() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "bb", "ccc");

        java.util.concurrent.CompletableFuture<java.util.Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(
                        keys,
                        k -> k.length()
                );

        java.util.Map<String, Integer> result = future.join();
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: exception in processor propagates as CompletionException")
    void testProcessInParallel_ExceptionPropagation() {
        java.util.List<String> keys = java.util.Arrays.asList("ok", "bad", "fine");

        java.util.concurrent.CompletableFuture<java.util.Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(
                        keys,
                        k -> {
                            if ("bad".equals(k)) {
                                throw new IllegalStateException("boom");
                            }
                            return k.length();
                        }
                );

        java.util.concurrent.CompletionException ex =
                assertThrows(java.util.concurrent.CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep first occurrence value")
    void testProcessInParallel_DuplicateKeys_FirstWins() {
        java.util.List<String> keys = java.util.Arrays.asList("x", "x");

        java.util.concurrent.atomic.AtomicInteger counter = new java.util.concurrent.atomic.AtomicInteger(0);

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(
                        keys,
                        k -> k + "#" + counter.incrementAndGet()
                );

        java.util.Map<String, String> result = future.join();
        assertEquals(1, result.size());
        assertEquals("x#1", result.get("x"));
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths: computes shortest distances in a weighted directed graph")
    void testFindShortestPaths_SimpleGraph() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("A", new java.util.HashMap<>());
        graph.put("B", new java.util.HashMap<>());
        graph.put("C", new java.util.HashMap<>());
        graph.put("D", new java.util.HashMap<>());
        graph.put("E", new java.util.HashMap<>()); // disconnected

        graph.get("A").put("B", 1);
        graph.get("A").put("C", 4);
        graph.get("B").put("C", 2);
        graph.get("B").put("D", 5);
        graph.get("C").put("D", 1);

        java.util.Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_InvalidInputs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("X", new java.util.HashMap<>());

        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    // shutdown test

    @Test
    @DisplayName("shutdown: can be called safely")
    void testShutdown_SafelyTerminates() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}