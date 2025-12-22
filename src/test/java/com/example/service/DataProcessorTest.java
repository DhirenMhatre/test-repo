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
    @DisplayName("Should instantiate DataProcessor successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    @Test
    @DisplayName("processDataPipeline: basic transformation, sorting, grouping, and deduplication")
    void testProcessDataPipeline_Basic() {
        java.util.List<String> input = java.util.List.of("apple", "apricot", "banana", "blueberry", "avocado", "banana");

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        input,
                        java.util.Objects::nonNull,
                        String::toUpperCase,
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(2, result.size());

        assertTrue(result.containsKey("A"));
        assertTrue(result.containsKey("B"));

        java.util.List<String> groupA = result.get("A");
        java.util.List<String> groupB = result.get("B");

        assertEquals(3, groupA.size(), "Expected 3 unique A-prefixed entries");
        assertEquals(2, groupB.size(), "Expected 'BANANA' deduped with 'BLUEBERRY' remaining");

        assertTrue(groupA.contains("APPLE"));
        assertTrue(groupA.contains("APRICOT"));
        assertTrue(groupA.contains("AVOCADO"));

        assertTrue(groupB.contains("BANANA"));
        assertTrue(groupB.contains("BLUEBERRY"));
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_EmptyAndNullInput() {
        java.util.Map<String, java.util.List<String>> resultNull =
                dataProcessor.<String, String>processDataPipeline(
                        null,
                        java.util.Objects::nonNull,
                        String::toUpperCase,
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        java.util.Map<String, java.util.List<String>> resultEmpty =
                dataProcessor.<String, String>processDataPipeline(
                        java.util.Collections.emptyList(),
                        java.util.Objects::nonNull,
                        String::toUpperCase,
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 after deduplication")
    void testProcessDataPipeline_DeduplicationAndLimitPerGroup() {
        java.util.List<String> data = new java.util.ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(String.format("a%03d", i));
        }
        // Add another group to ensure only 'a' group hits the limit
        for (int i = 0; i < 10; i++) {
            data.add(String.format("b%03d", i));
        }

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        java.util.Objects::nonNull,
                        s -> s, // identity transformer
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertTrue(result.containsKey("a"));
        assertTrue(result.containsKey("b"));

        java.util.List<String> groupA = result.get("a");
        java.util.List<String> groupB = result.get("b");

        assertEquals(100, groupA.size(), "Group 'a' should be limited to 100");
        assertEquals(10, groupB.size(), "Group 'b' should contain all 10 unique entries");

        assertTrue(groupA.contains("a000"));
        assertFalse(groupA.contains("a149"), "Entries beyond first 100 (by sort order) should be excluded");
        // Ensure distinct
        long distinctCount = groupA.stream().distinct().count();
        assertEquals(groupA.size(), distinctCount, "Group 'a' should be distinct after deduplication");
    }

    @Test
    @DisplayName("processDataPipeline: filters out nulls produced by transformer")
    void testProcessDataPipeline_FiltersTransformerNulls() {
        java.util.List<String> data = java.util.List.of("keep", "nullify", "also");

        java.util.Map<String, java.util.List<String>> result =
                dataProcessor.<String, String>processDataPipeline(
                        data,
                        java.util.Objects::nonNull,
                        s -> "nullify".equals(s) ? null : s.toUpperCase(),
                        s -> s.substring(0, 1),
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(2, result.size(), "Only 'keep' and 'also' should remain after transformer nulls filtered out");

        assertTrue(result.containsKey("K"));
        assertTrue(result.containsKey("A"));
        assertEquals(1, result.get("K").size());
        assertEquals(1, result.get("A").size());
        assertTrue(result.get("K").contains("KEEP"));
        assertTrue(result.get("A").contains("ALSO"));
    }

    @Test
    @DisplayName("calculateStatistics: even count dataset yields correct mean, median, quartiles, stddev, no outliers")
    void testCalculateStatistics_EvenCount() {
        java.util.List<Double> values = java.util.List.of(1d, 2d, 3d, 4d, 5d, 6d, 7d, 8d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(4.5, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);

        // Population variance for 1..8 is 5.25; stddev = sqrt(5.25)
        double expectedStdDev = Math.sqrt(5.25);
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-12);

        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: odd count dataset yields correct stats")
    void testCalculateStatistics_OddCount() {
        java.util.List<Double> values = java.util.List.of(1d, 2d, 3d, 4d, 5d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(3.0, result.getMean(), 1e-9);
        assertEquals(3.0, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(4.0, result.getQ3(), 1e-9);

        double expectedStdDev = Math.sqrt(2.0); // population variance for 1..5 is 2
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-12);
    }

    @Test
    @DisplayName("calculateStatistics: detects outliers via IQR and computes stddev (population)")
    void testCalculateStatistics_WithOutliers() {
        java.util.List<Double> values = java.util.List.of(1d, 2d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // Mean
        double expectedMean = 117.0 / 7.0;
        assertEquals(expectedMean, result.getMean(), 1e-12);

        // Median and quartiles per implementation
        assertEquals(3.0, result.getMedian(), 1e-12);
        assertEquals(2.0, result.getQ1(), 1e-12);
        assertEquals(5.0, result.getQ3(), 1e-12);

        // Outliers: only 100
        assertNotNull(result.getOutliers());
        assertEquals(1, result.getOutliers().size());
        assertEquals(100.0, result.getOutliers().get(0), 1e-12);

        // Population standard deviation
        double variance = 0.0;
        for (double v : values) {
            double d = v - expectedMean;
            variance += d * d;
        }
        variance /= values.size();
        double expectedStdDev = Math.sqrt(variance);

        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: throws for null or empty list")
    void testCalculateStatistics_NullOrEmpty_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(java.util.Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult: outliers list is unmodifiable")
    void testStatisticalResult_OutliersUnmodifiable() {
        java.util.List<Double> values = java.util.List.of(1d, 2d, 3d, 4d, 100d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        java.util.List<Double> outliers = result.getOutliers();

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(42.0));
    }

    @Test
    @DisplayName("processInParallel: processes all keys and aggregates results")
    void testProcessInParallel_Success() {
        java.util.List<String> keys = java.util.List.of("a", "b", "c");

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.processInParallel(keys, String::toUpperCase);

        java.util.Map<String, String> result = future.join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));
    }

    @Test
    @DisplayName("processInParallel: propagates processing failure as CompletionException on join")
    void testProcessInParallel_ExceptionPropagates() {
        java.util.List<String> keys = java.util.List.of("ok1", "bad", "ok2");

        java.util.concurrent.CompletableFuture<java.util.Map<String, String>> future =
                dataProcessor.processInParallel(keys, key -> {
                    if ("bad".equals(key)) {
                        throw new IllegalStateException("boom");
                    }
                    return key.toUpperCase();
                });

        assertThrows(java.util.concurrent.CompletionException.class, future::join);
    }

    @Test
    @DisplayName("findShortestPaths: computes correct distances including unreachable nodes")
    void testFindShortestPaths_BasicGraph() {
        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();

        java.util.Map<String, Integer> aNeighbors = new java.util.HashMap<>();
        aNeighbors.put("B", 1);
        aNeighbors.put("C", 4);
        graph.put("A", aNeighbors);

        java.util.Map<String, Integer> bNeighbors = new java.util.HashMap<>();
        bNeighbors.put("C", 2);
        bNeighbors.put("D", 6);
        graph.put("B", bNeighbors);

        java.util.Map<String, Integer> cNeighbors = new java.util.HashMap<>();
        cNeighbors.put("D", 3);
        graph.put("C", cNeighbors);

        graph.put("D", new java.util.HashMap<>());
        graph.put("E", new java.util.HashMap<>()); // unreachable

        java.util.Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(5, distances.size());
        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // via A->B->C
        assertEquals(6, distances.get("D").intValue()); // via A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid inputs")
    void testFindShortestPaths_InvalidInput_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        java.util.Map<String, java.util.Map<String, Integer>> graph = new java.util.HashMap<>();
        graph.put("X", new java.util.HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}