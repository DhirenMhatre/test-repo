package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;

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
    @DisplayName("processDataPipeline: returns empty map for null input")
    void testProcessDataPipeline_NullInput() {
        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                String::length,
                len -> len % 2 == 0 ? "even" : "odd",
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for empty input")
    void testProcessDataPipeline_EmptyInput() {
        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                String::length,
                len -> len % 2 == 0 ? "even" : "odd",
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filters, maps (with nulls), sorts, groups, distincts and limits")
    void testProcessDataPipeline_BasicPipeline() {
        List<String> data = Arrays.asList("apple", "banana", "pear", "kiwi", "apple", "NULL", "plum", "banana");

        Predicate<String> filter = Objects::nonNull; // allow all non-null
        Function<String, Integer> transformer = s -> "plum".equals(s) ? null : s.length(); // map "plum" to null
        Function<Integer, String> grouper = len -> (len % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        // Expected after mapping (excluding null for "plum"): lengths [5,6,4,4,5,4,6]
        // Sorted globally: [4,4,4,5,5,6,6]
        // Groups with distinct and limit:
        // even: [4,6], odd: [5]
        assertNotNull(result);
        assertEquals(2, result.size());
        assertTrue(result.containsKey("even"));
        assertTrue(result.containsKey("odd"));
        assertEquals(Arrays.asList(4, 6), result.get("even"));
        assertEquals(Collections.singletonList(5), result.get("odd"));
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 after distinct")
    void testProcessDataPipeline_GroupLimit() {
        // Create 150 integers, all grouped into the same group "all"
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                data,
                i -> true,
                i -> i, // identity
                i -> "all",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.containsKey("all"));
        List<Integer> list = result.get("all");
        assertEquals(100, list.size());
        // Since sorted asc, then distinct, then limit(100), expect 0..99
        for (int i = 0; i < 100; i++) {
            assertEquals(i, list.get(i));
        }
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics: throws on null input")
    void testCalculateStatistics_NullInput_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws on empty input")
    void testCalculateStatistics_EmptyInput_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev (population) and outliers - even count")
    void testCalculateStatistics_EvenCount() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 6d, 7d, 8d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(4.5, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        // Percentile method: index = ceil(p/100 * n) - 1
        // Q1 = 2, Q3 = 6 for 1..8
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);
        // Population std dev for 1..8 is sqrt(5.25) ≈ 2.291287847
        assertEquals(2.291287847, result.getStandardDeviation(), 1e-6);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: detects outliers and computes stats correctly - with outlier present")
    void testCalculateStatistics_WithOutlier() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 100d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(21.6, result.getMean(), 1e-9);
        assertEquals(2.0, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(3.0, result.getQ3(), 1e-9);
        // Population std dev computed above ≈ 39.20285
        assertEquals(39.20285, result.getStandardDeviation(), 1e-3);
        assertEquals(Collections.singletonList(100d), result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: single element has zero stddev and quartiles equal to value")
    void testCalculateStatistics_SingleElement() {
        List<Double> values = Collections.singletonList(42d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(42.0, result.getMean(), 1e-9);
        assertEquals(42.0, result.getMedian(), 1e-9);
        assertEquals(42.0, result.getQ1(), 1e-9);
        assertEquals(42.0, result.getQ3(), 1e-9);
        assertEquals(0.0, result.getStandardDeviation(), 1e-9);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("StatisticalResult: outliers list is unmodifiable")
    void testStatisticalResult_OutliersImmutability() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 100d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        List<Double> outliers = result.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(200d));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel: processes keys successfully and returns map")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");
        Function<String, Integer> processor = String::length;

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, processor);

        Map<String, Integer> result = future.join();
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys result in single entry")
    void testProcessInParallel_DuplicateKeys() {
        List<String> keys = Arrays.asList("dup", "dup", "dup");
        Function<String, Integer> processor = String::length;

        Map<String, Integer> result = dataProcessor.<Integer>processInParallel(keys, processor).join();
        assertEquals(1, result.size());
        assertEquals(Integer.valueOf(3), result.get("dup"));
    }

    @Test
    @DisplayName("processInParallel: processor failure completes future exceptionally with wrapped message")
    void testProcessInParallel_ProcessorThrows() {
        List<String> keys = Arrays.asList("ok1", "err", "ok2");
        Function<String, Integer> processor = k -> {
            if ("err".equals(k)) {
                throw new IllegalStateException("boom");
            }
            return k.length();
        };

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, processor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: err"));
    }

    @Test
    @DisplayName("processInParallel: after shutdown, new submissions fail")
    void testProcessInParallel_AfterShutdownFails() {
        dataProcessor.shutdown();
        List<String> keys = Arrays.asList("a", "b");
        Function<String, String> processor = k -> k.toUpperCase(Locale.ROOT);

        CompletableFuture<Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, processor);

        assertThrows(CompletionException.class, future::join);
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths: computes shortest paths correctly on directed graph")
    void testFindShortestPaths_ShortestPaths() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("C", new HashMap<>());
        graph.put("D", new HashMap<>());

        graph.get("A").put("B", 1);
        graph.get("A").put("C", 4);
        graph.get("B").put("C", 2);
        graph.get("B").put("D", 5);
        graph.get("C").put("D", 1);

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph")
    void testFindShortestPaths_NullGraph_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: throws when start node missing")
    void testFindShortestPaths_MissingStartNode_Throws() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}