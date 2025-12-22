package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import java.util.*;
import java.util.concurrent.CompletionException;

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

    // processDataPipeline tests

    @Test
    @DisplayName("processDataPipeline: Basic transformation, sorting, grouping, and deduplication")
    void testProcessDataPipeline_BasicFlowStrings() {
        List<String> data = Arrays.asList(
                "apple", "apricot", "banana", "avocado", "blueberry", "apple", "banana", "avocado"
        );

        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                data,
                s -> s.startsWith("a") || s.startsWith("b"),
                String::toUpperCase,
                s -> s.substring(0, 1),
                Comparator.naturalOrder()
        );

        assertEquals(2, result.size());
        assertTrue(result.containsKey("A"));
        assertTrue(result.containsKey("B"));

        assertEquals(Arrays.asList("APPLE", "APRICOT", "AVOCADO"), result.get("A"));
        assertEquals(Arrays.asList("BANANA", "BLUEBERRY"), result.get("B"));
    }

    @Test
    @DisplayName("processDataPipeline: Returns empty map for null input")
    void testProcessDataPipeline_NullInput() {
        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                null,
                x -> true,
                x -> x,
                x -> "ALL",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: Returns empty map for empty input")
    void testProcessDataPipeline_EmptyInput() {
        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                Collections.emptyList(),
                x -> true,
                x -> x,
                x -> "ALL",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: Filters out nulls produced by transformer")
    void testProcessDataPipeline_TransformerProducesNulls() {
        List<Integer> data = Arrays.asList(1, 2, 3, 4);

        Map<String, List<String>> result = dataProcessor.<Integer, String>processDataPipeline(
                data,
                n -> true,
                n -> (n % 2 == 0) ? null : String.valueOf(n),
                s -> "ODD",
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        List<String> oddGroup = result.get("ODD");
        assertNotNull(oddGroup);
        assertEquals(Arrays.asList("1", "3"), oddGroup);
    }

    @Test
    @DisplayName("processDataPipeline: Applies per-group limit of 100 after deduplication")
    void testProcessDataPipeline_GroupLimitAndDistinct() {
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                data,
                n -> true,
                n -> n,
                n -> "GROUP",
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        List<Integer> group = result.get("GROUP");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics: Correct statistics for even-sized dataset (no outliers)")
    void testCalculateStatistics_EvenCount() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 6d, 7d, 8d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(4.5, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(5.25), result.getStandardDeviation(), 1e-9);
        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: Detects outliers and computes stats for odd-sized dataset")
    void testCalculateStatistics_OddWithOutlier() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(22.0, result.getMean(), 1e-9);
        assertEquals(3.0, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(4.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(1522.0), result.getStandardDeviation(), 1e-6);

        assertNotNull(result.getOutliers());
        assertEquals(1, result.getOutliers().size());
        assertEquals(100.0, result.getOutliers().get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: Throws IllegalArgumentException for null input")
    void testCalculateStatistics_ThrowsOnNull() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: Throws IllegalArgumentException for empty input")
    void testCalculateStatistics_ThrowsOnEmpty() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult: Outliers list is unmodifiable")
    void testStatisticalResult_OutliersUnmodifiable() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 100d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        List<Double> outliers = result.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999d));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel: Processes keys and aggregates results successfully")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("alpha", "beta", "gamma");

        Map<String, Integer> map = dataProcessor.<Integer>processInParallel(
                keys,
                s -> s.length()
        ).join();

        assertEquals(3, map.size());
        assertEquals(Integer.valueOf(5), map.get("alpha"));
        assertEquals(Integer.valueOf(4), map.get("beta"));
        assertEquals(Integer.valueOf(5), map.get("gamma"));
    }

    @Test
    @DisplayName("processInParallel: Handles exceptions and completes exceptionally")
    void testProcessInParallel_Exception() {
        List<String> keys = Arrays.asList("ok", "fail");

        CompletionException ex = assertThrows(CompletionException.class, () ->
                dataProcessor.<String>processInParallel(
                        keys,
                        k -> {
                            if ("fail".equals(k)) {
                                throw new IllegalArgumentException("bad");
                            }
                            return k.toUpperCase();
                        }
                ).join()
        );

        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: fail"));
    }

    @Test
    @DisplayName("processInParallel: Duplicate keys keep first value (merge function retains existing)")
    void testProcessInParallel_DuplicateKeys() {
        List<String> keys = Arrays.asList("dup", "dup", "other");

        Map<String, Integer> map = dataProcessor.<Integer>processInParallel(
                keys,
                s -> s.length()
        ).join();

        // Only two unique keys should be present
        assertEquals(2, map.size());
        assertEquals(Integer.valueOf(3), map.get("dup"));
        assertEquals(Integer.valueOf(5), map.get("other"));
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths: Computes shortest paths in a directed weighted graph")
    void testFindShortestPaths_Basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<String, Integer>() {{
            put("B", 1);
            put("C", 4);
        }});
        graph.put("B", new HashMap<String, Integer>() {{
            put("C", 2);
            put("D", 5);
        }});
        graph.put("C", new HashMap<String, Integer>() {{
            put("D", 1);
        }});
        graph.put("D", new HashMap<>());
        graph.put("E", new HashMap<>()); // Unreachable node

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(Integer.valueOf(0), distances.get("A"));
        assertEquals(Integer.valueOf(1), distances.get("B"));
        assertEquals(Integer.valueOf(3), distances.get("C")); // A->B->C
        assertEquals(Integer.valueOf(4), distances.get("D")); // A->B->C->D
        assertEquals(Integer.valueOf(Integer.MAX_VALUE), distances.get("E")); // Unreachable
    }

    @Test
    @DisplayName("findShortestPaths: Throws IllegalArgumentException for null graph")
    void testFindShortestPaths_NullGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: Throws IllegalArgumentException when start node not in graph")
    void testFindShortestPaths_InvalidStartNode() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    // shutdown tests

    @Test
    @DisplayName("shutdown: Should not throw when called")
    void testShutdown_NoThrow() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}