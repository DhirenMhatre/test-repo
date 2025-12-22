package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.Comparator;

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
    @DisplayName("processDataPipeline: Filters, maps, sorts, groups, and deduplicates correctly")
    void testProcessDataPipeline_BasicFlow() {
        List<Integer> data = Arrays.asList(1, 2, 2, 3, 4, 5, 6, 6);

        Predicate<Integer> filter = v -> true;
        Function<Integer, Integer> transformer = v -> v; // identity
        Function<Integer, String> grouper = v -> v % 2 == 0 ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.<Integer>naturalOrder().reversed(); // descending

        Map<String, List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertNotNull(result);
        assertTrue(result.containsKey("even"));
        assertTrue(result.containsKey("odd"));

        // Distinct within each group, in sorted (descending) order
        assertEquals(Arrays.asList(6, 4, 2), result.get("even"));
        assertEquals(Arrays.asList(5, 3, 1), result.get("odd"));
    }

    @Test
    @DisplayName("processDataPipeline: Returns empty map for null or empty input")
    void testProcessDataPipeline_NullOrEmptyInput() {
        Predicate<String> filter = s -> true;
        Function<String, Integer> transformer = String::length;
        Function<Integer, String> grouper = len -> len.toString();
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> resultNull =
                dataProcessor.<String, Integer>processDataPipeline(null, filter, transformer, grouper, sorter);
        Map<String, List<Integer>> resultEmpty =
                dataProcessor.<String, Integer>processDataPipeline(Collections.emptyList(), filter, transformer, grouper, sorter);

        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: Transformer returning null is filtered out")
    void testProcessDataPipeline_NullTransformerResultsFilteredOut() {
        List<String> data = Arrays.asList("1", "a", "2", "b", "3");

        Predicate<String> filter = s -> true;
        Function<String, Integer> transformer = s -> {
            try {
                return Integer.valueOf(s);
            } catch (NumberFormatException e) {
                return null; // will be filtered out by .filter(Objects::nonNull)
            }
        };
        Function<Integer, String> grouper = v -> v % 2 == 0 ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertNotNull(result);
        assertEquals(Arrays.asList(2), result.get("even"));
        assertEquals(Arrays.asList(1, 3), result.get("odd"));
    }

    @Test
    @DisplayName("processDataPipeline: Respects per-group limit of 100 after deduplication")
    void testProcessDataPipeline_PerGroupLimit() {
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }

        Predicate<Integer> filter = v -> true;
        Function<Integer, Integer> transformer = v -> v;
        Function<Integer, String> grouper = v -> "group";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertNotNull(result);
        assertTrue(result.containsKey("group"));
        List<Integer> list = result.get("group");
        assertEquals(100, list.size());
        assertEquals(0, list.get(0).intValue());
        assertEquals(99, list.get(99).intValue());
    }

    @Test
    @DisplayName("calculateStatistics: Computes mean, median, quartiles, stddev, and outliers (even count)")
    void testCalculateStatistics_EvenCount() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(2.5, result.getMean(), 1e-9);
        assertEquals(2.5, result.getMedian(), 1e-9);

        // Percentile method as implemented: q1 = 1.0, q3 = 3.0
        assertEquals(1.0, result.getQ1(), 1e-9);
        assertEquals(3.0, result.getQ3(), 1e-9);

        // Population std dev for [1,2,3,4] with mean 2.5 is sqrt(1.25) ≈ 1.1180
        assertEquals(1.118033988749895, result.getStandardDeviation(), 1e-12);

        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: Detects outliers and computes stats (odd count with outlier)")
    void testCalculateStatistics_OddCount_WithOutliers() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 9d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(3.4, result.getMean(), 1e-9);
        assertEquals(2.0, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(3.0, result.getQ3(), 1e-9);

        // Variance = 8.24 -> stddev ≈ 2.87054001888
        assertEquals(2.870540018881465, result.getStandardDeviation(), 1e-12);

        assertEquals(1, result.getOutliers().size());
        assertEquals(9.0, result.getOutliers().get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: Throws IllegalArgumentException for null or empty list")
    void testCalculateStatistics_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult: Outliers list is unmodifiable")
    void testStatisticalResult_OutliersImmutability() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 9d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        List<Double> outliers = result.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(10.0));
    }

    @Test
    @DisplayName("processInParallel: Completes successfully and returns map of results")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");
        Function<String, Integer> processor = String::length;

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, processor);

        Map<String, Integer> result = future.join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: Propagates exceptions via CompletionException")
    void testProcessInParallel_ExceptionPropagation() {
        List<String> keys = Arrays.asList("ok1", "fail", "ok2");
        Function<String, Integer> processor = key -> {
            if ("fail".equals(key)) {
                throw new RuntimeException("boom");
            }
            return key.length();
        };

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, processor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: fail"));
    }

    @Test
    @DisplayName("findShortestPaths: Computes shortest paths correctly and leaves unreachable as MAX_VALUE")
    void testFindShortestPaths_Basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();

        Map<String, Integer> aEdges = new HashMap<>();
        aEdges.put("B", 1);
        aEdges.put("C", 4);
        graph.put("A", aEdges);

        Map<String, Integer> bEdges = new HashMap<>();
        bEdges.put("C", 2);
        bEdges.put("D", 5);
        graph.put("B", bEdges);

        Map<String, Integer> cEdges = new HashMap<>();
        cEdges.put("D", 1);
        graph.put("C", cEdges);

        graph.put("D", new HashMap<>()); // no outgoing edges
        graph.put("E", new HashMap<>()); // isolated node

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: Throws IllegalArgumentException for invalid graph or start node")
    void testFindShortestPaths_Invalid() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: Can be called without exceptions")
    void testShutdown_NoException() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
        // Reassign a new instance for tearDown to shutdown again safely
        dataProcessor = new DataProcessor();
    }
}