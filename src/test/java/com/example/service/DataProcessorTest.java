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

    @Test
    @DisplayName("processDataPipeline: basic filtering, mapping, sorting, grouping, distinct")
    void testProcessDataPipeline_BasicFlow() {
        java.util.List<String> data = java.util.Arrays.asList(
                "apple", "banana", "apricot", "banana", "avocado", "", "cherry"
        );

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        s -> s != null && !s.isEmpty(),
                        String::toUpperCase,
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(3, result.size());

        java.util.List<String> groupA = result.get("A");
        java.util.List<String> groupB = result.get("B");
        java.util.List<String> groupC = result.get("C");

        assertNotNull(groupA);
        assertNotNull(groupB);
        assertNotNull(groupC);

        assertEquals(java.util.Arrays.asList("APPLE", "APRICOT", "AVOCADO"), groupA);
        assertEquals(java.util.Arrays.asList("BANANA"), groupB);
        assertEquals(java.util.Arrays.asList("CHERRY"), groupC);
    }

    @Test
    @DisplayName("processDataPipeline: null data returns empty map")
    void testProcessDataPipeline_NullData() {
        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        null,
                        s -> true,
                        s -> s,
                        s -> "group",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: empty data returns empty map")
    void testProcessDataPipeline_EmptyData() {
        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        java.util.Collections.emptyList(),
                        s -> true,
                        s -> s,
                        s -> "group",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filters out null transformer results and removes duplicates")
    void testProcessDataPipeline_NullOutputsAndDistinct() {
        java.util.List<String> data = new java.util.ArrayList<>();
        data.add("x");
        data.add("x");     // duplicate
        data.add("y");     // will be transformed to null
        data.add(null);    // filtered by predicate
        data.add("zz");

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        s -> s != null,
                        s -> "y".equals(s) ? null : s, // transformer returns null for "y"
                        s -> "group",
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        java.util.List<String> group = result.get("group");
        assertNotNull(group);
        assertEquals(java.util.Arrays.asList("x", "zz"), group);
    }

    @Test
    @DisplayName("processDataPipeline: enforces limit of 100 items per group after distinct")
    void testProcessDataPipeline_LimitPerGroup() {
        java.util.List<Integer> data = new java.util.ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }

        java.util.Map<String, java.util.List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        data,
                        v -> true,
                        v -> v, // identity transform
                        v -> "all",
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        java.util.List<Integer> group = result.get("all");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev, outliers")
    void testCalculateStatistics_Basic() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // Expected calculations based on DataProcessor logic
        java.util.List<Double> sorted = new java.util.ArrayList<>(values);
        java.util.Collections.sort(sorted);

        double expectedMean = sorted.stream().mapToDouble(Double::doubleValue).average().orElse(0.0);
        double expectedMedian = median(sorted);
        double expectedQ1 = percentile(sorted, 25);
        double expectedQ3 = percentile(sorted, 75);
        double expectedStdDev = populationStdDev(sorted, expectedMean);
        java.util.List<Double> expectedOutliers = outliers(sorted, expectedQ1, expectedQ3);

        assertEquals(expectedMean, result.getMean(), 1e-9);
        assertEquals(expectedMedian, result.getMedian(), 1e-9);
        assertEquals(expectedQ1, result.getQ1(), 1e-9);
        assertEquals(expectedQ3, result.getQ3(), 1e-9);
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-9);
        assertEquals(expectedOutliers, result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: single element list yields that value and zero stddev, no outliers")
    void testCalculateStatistics_SingleElement() {
        java.util.List<Double> values = java.util.Collections.singletonList(42.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(42.0, result.getMean(), 1e-9);
        assertEquals(42.0, result.getMedian(), 1e-9);
        assertEquals(42.0, result.getQ1(), 1e-9);
        assertEquals(42.0, result.getQ3(), 1e-9);
        assertEquals(0.0, result.getStandardDeviation(), 1e-9);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: throws on null or empty list")
    void testCalculateStatistics_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(java.util.Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys and returns completed map")
    void testProcessInParallel_Success() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "bb", "ccc");

        java.util.concurrent.CompletableFuture<java.util.Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, String::length);

        java.util.Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: handles duplicate keys by keeping first result")
    void testProcessInParallel_DuplicateKeys() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "a", "b");

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, String::toUpperCase);

        java.util.Map<String, String> result = future.join();

        assertEquals(2, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
    }

    @Test
    @DisplayName("processInParallel: propagates exception when any task fails")
    void testProcessInParallel_Exception() {
        java.util.List<String> keys = java.util.Arrays.asList("ok", "fail", "also-ok");

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, k -> {
                    if ("fail".equals(k)) {
                        throw new RuntimeException("boom");
                    }
                    return k.toUpperCase();
                });

        java.util.concurrent.CompletionException ex =
                assertThrows(java.util.concurrent.CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: fail"));
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances including unreachable nodes")
    void testFindShortestPaths_Basic() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();

        java.util.Map<String, Integer> edgesA = new java.util.HashMap<>();
        edgesA.put("B", 1);
        edgesA.put("C", 4);
        java.util.Map<String, Integer> edgesB = new java.util.HashMap<>();
        edgesB.put("C", 2);
        edgesB.put("D", 5);
        java.util.Map<String, Integer> edgesC = new java.util.HashMap<>();
        edgesC.put("D", 1);
        java.util.Map<String, Integer> edgesD = new java.util.HashMap<>();
        java.util.Map<String, Integer> edgesE = new java.util.HashMap<>();

        graph.put("A", edgesA);
        graph.put("B", edgesB);
        graph.put("C", edgesC);
        graph.put("D", edgesD);
        graph.put("E", edgesE); // unreachable from A

        java.util.Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C")); // A->B->C (1 + 2)
        assertEquals(4, (int) distances.get("D")); // A->B->C->D (1 + 2 + 1)
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E")); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_InvalidInputs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("A", new java.util.HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    // Helper methods for statistics expectations (mirror DataProcessor logic)

    private static double median(java.util.List<Double> sorted) {
        int size = sorted.size();
        if (size % 2 == 0) {
            return (sorted.get(size / 2 - 1) + sorted.get(size / 2)) / 2.0;
        } else {
            return sorted.get(size / 2);
        }
        }

    private static double percentile(java.util.List<Double> sorted, double percentile) {
        int index = (int) Math.ceil((percentile / 100.0) * sorted.size()) - 1;
        index = Math.max(0, Math.min(index, sorted.size() - 1));
        return sorted.get(index);
    }

    private static double populationStdDev(java.util.List<Double> sorted, double mean) {
        double variance = sorted.stream().mapToDouble(v -> Math.pow(v - mean, 2)).average().orElse(0.0);
        return Math.sqrt(variance);
    }

    private static java.util.List<Double> outliers(java.util.List<Double> sorted, double q1, double q3) {
        double iqr = q3 - q1;
        double lower = q1 - 1.5 * iqr;
        double upper = q3 + 1.5 * iqr;
        java.util.List<Double> out = new java.util.ArrayList<>();
        for (Double v : sorted) {
            if (v < lower || v > upper) {
                out.add(v);
            }
        }
        return out;
    }
}