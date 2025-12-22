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

    @Test
    @DisplayName("Constructor should create instance successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    @Test
    @DisplayName("processDataPipeline: should return empty map for null or empty input")
    void testProcessDataPipeline_NullOrEmpty() {
        java.util.Map<String, java.util.List<Integer>> r1 =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        null,
                        x -> true,
                        x -> x,
                        Object::toString,
                        java.util.Comparator.naturalOrder()
                );
        assertTrue(r1.isEmpty());

        java.util.Map<String, java.util.List<Integer>> r2 =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        new java.util.ArrayList<Integer>(),
                        x -> true,
                        x -> x,
                        Object::toString,
                        java.util.Comparator.naturalOrder()
                );
        assertTrue(r2.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filter, transform, group, sort, and deduplicate correctly")
    void testProcessDataPipeline_FilterTransformGroupSortDedup() {
        java.util.List<Integer> data = java.util.Arrays.asList(5, 4, 3, 2, 1, 2, 3, 4, 4, 5);

        java.util.Map<String, java.util.List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        data,
                        v -> v != null && v > 1,
                        v -> v, // identity transform
                        v -> (v % 2 == 0) ? "even" : "odd",
                        java.util.Comparator.naturalOrder()
                );

        assertEquals(2, result.size());
        assertTrue(result.containsKey("even"));
        assertTrue(result.containsKey("odd"));

        java.util.List<Integer> evens = result.get("even");
        java.util.List<Integer> odds = result.get("odd");

        assertEquals(java.util.Arrays.asList(2, 4), evens);
        assertEquals(java.util.Arrays.asList(3, 5), odds);
    }

    @Test
    @DisplayName("processDataPipeline: limit to 100 per group after deduplication")
    void testProcessDataPipeline_LimitPerGroup() {
        java.util.List<Integer> data = new java.util.ArrayList<>();
        for (int i = 1; i <= 150; i++) {
            data.add(i);
        }

        java.util.Map<String, java.util.List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        data,
                        v -> true,
                        v -> v, // identity
                        v -> "all",
                        java.util.Comparator.naturalOrder()
                );

        assertEquals(1, result.size());
        java.util.List<Integer> list = result.get("all");
        assertNotNull(list);
        assertEquals(100, list.size());
        assertEquals(1, list.get(0));
        assertEquals(100, list.get(99));
    }

    @Test
    @DisplayName("calculateStatistics: should throw for null or empty list")
    void testCalculateStatistics_NullOrEmpty_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(new java.util.ArrayList<Double>()));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev, and outliers (even-sized list with outlier)")
    void testCalculateStatistics_KnownDataset() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // Compute expected using the same algorithmic rules as DataProcessor
        java.util.List<Double> sorted = new java.util.ArrayList<>(values);
        java.util.Collections.sort(sorted);

        double mean = sorted.stream().mapToDouble(Double::doubleValue).average().orElse(0.0);
        double median = medianOfSorted(sorted);
        double q1 = percentile(sorted, 25.0);
        double q3 = percentile(sorted, 75.0);
        double iqr = q3 - q1;
        double lower = q1 - 1.5 * iqr;
        double upper = q3 + 1.5 * iqr;

        java.util.List<Double> expectedOutliers = new java.util.ArrayList<>();
        for (double v : sorted) {
            if (v < lower || v > upper) expectedOutliers.add(v);
        }

        double variance = 0.0;
        for (double v : sorted) {
            double d = v - mean;
            variance += d * d;
        }
        variance /= sorted.size();
        double stdDev = Math.sqrt(variance);

        assertEquals(mean, result.getMean(), 1e-9);
        assertEquals(median, result.getMedian(), 1e-9);
        assertEquals(q1, result.getQ1(), 1e-9);
        assertEquals(q3, result.getQ3(), 1e-9);
        assertEquals(stdDev, result.getStandardDeviation(), 1e-9);
        assertEquals(expectedOutliers, result.getOutliers());
        assertEquals(java.util.Arrays.asList(100.0), result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: single-element list produces identical quartiles and zero stddev with no outliers")
    void testCalculateStatistics_SingleElement() {
        java.util.List<Double> values = java.util.Arrays.asList(5.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(5.0, result.getMean(), 1e-9);
        assertEquals(5.0, result.getMedian(), 1e-9);
        assertEquals(5.0, result.getQ1(), 1e-9);
        assertEquals(5.0, result.getQ3(), 1e-9);
        assertEquals(0.0, result.getStandardDeviation(), 1e-9);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("StatisticalResult: outliers list is unmodifiable")
    void testStatisticalResult_OutliersUnmodifiable() {
        java.util.List<Double> values = java.util.Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        java.util.List<Double> outliers = result.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999.0));
        assertEquals(java.util.Arrays.asList(100.0), outliers);
    }

    @Test
    @DisplayName("processInParallel: returns map of processed results for all keys")
    void testProcessInParallel_Success() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "b", "c");
        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, String::toUpperCase);

        java.util.Map<String, String> result = future.join();
        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep first occurrence (merge keeps existing)")
    void testProcessInParallel_DuplicateKeysKeepsFirst() {
        java.util.List<String> keys = java.util.Arrays.asList("a", "a");
        java.util.concurrent.atomic.AtomicInteger counter = new java.util.concurrent.atomic.AtomicInteger(0);

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, k -> k + "#" + counter.getAndIncrement());

        java.util.Map<String, String> result = future.join();
        assertEquals(1, result.size());
        assertEquals("a#0", result.get("a"));
    }

    @Test
    @DisplayName("processInParallel: propagates exceptions from processor")
    void testProcessInParallel_PropagatesException() {
        java.util.List<String> keys = java.util.Arrays.asList("ok", "fail", "ok2");
        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, k -> {
                    if ("fail".equals(k)) throw new IllegalStateException("boom");
                    return k;
                });

        java.util.concurrent.CompletionException ex =
                assertThrows(java.util.concurrent.CompletionException.class, future::join);
        assertNotNull(ex.getCause());
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("A", new java.util.HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    @Test
    @DisplayName("findShortestPaths: computes correct shortest distances including unreachable nodes")
    void testFindShortestPaths_Computation() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();

        java.util.Map<String, Integer> aNeighbors = new java.util.HashMap<>();
        aNeighbors.put("B", 1);
        aNeighbors.put("C", 4);
        aNeighbors.put("D", 10);
        graph.put("A", aNeighbors);

        java.util.Map<String, Integer> bNeighbors = new java.util.HashMap<>();
        bNeighbors.put("C", 2);
        bNeighbors.put("D", 5);
        graph.put("B", bNeighbors);

        java.util.Map<String, Integer> cNeighbors = new java.util.HashMap<>();
        cNeighbors.put("D", 1);
        graph.put("C", cNeighbors);

        java.util.Map<String, Integer> dNeighbors = new java.util.HashMap<>();
        dNeighbors.put("E", 1);
        graph.put("D", dNeighbors);

        graph.put("E", new java.util.HashMap<>()); // sink
        graph.put("F", new java.util.HashMap<>()); // unreachable from A

        java.util.Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(5, distances.get("E").intValue()); // ... ->D->E
        assertEquals(Integer.MAX_VALUE, distances.get("F").intValue()); // unreachable
    }

    @Test
    @DisplayName("shutdown: prevents further parallel submissions")
    void testShutdown_PreventsFurtherParallelSubmissions() {
        dataProcessor.shutdown();
        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.<String>processInParallel(java.util.Arrays.asList("x"), k -> k);
        assertThrows(java.util.concurrent.CompletionException.class, future::join);
    }

    // Helper methods to compute expected statistical values consistent with DataProcessor
    private static double medianOfSorted(java.util.List<Double> sorted) {
        int n = sorted.size();
        if (n % 2 == 0) {
            return (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2.0;
        } else {
            return sorted.get(n / 2);
        }
    }

    private static double percentile(java.util.List<Double> sorted, double p) {
        if (p < 0 || p > 100) throw new IllegalArgumentException("percentile");
        int index = (int) Math.ceil((p / 100.0) * sorted.size()) - 1;
        index = Math.max(0, Math.min(index, sorted.size() - 1));
        return sorted.get(index);
    }
}