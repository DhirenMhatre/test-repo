package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

import java.util.stream.Stream;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;

class DataProcessorTest {

    private DataProcessor dataProcessor;

    private Predicate<String> mockFilter;

    private Function<String, Integer> mockTransformer;

    private Function<Integer, String> mockGrouper;

    private Comparator<Integer> mockComparator;

    private Function<String, Integer> mockAsyncProcessor;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();

        mockFilter = s -> s != null && s.length() >= 2;

        mockTransformer = String::length;

        mockGrouper = i -> (i % 2 == 0) ? "even" : "odd";

        mockComparator = Integer::compareTo;

        mockAsyncProcessor = s -> {
            if ("bad".equals(s)) {
                throw new RuntimeException("bad key");
            }
            if (s != null && s.startsWith("k")) {
                try {
                    return Integer.parseInt(s.substring(1));
                } catch (NumberFormatException e) {
                    return 0;
                }
            }
            // For duplicate test and general fallback
            return 1;
        };
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline returns empty map for null or empty input")
    void testProcessDataPipeline_NullOrEmpty() {
        Map<String, List<Integer>> resultNull =
                dataProcessor.<String, Integer>processDataPipeline(
                        null,
                        s -> true,
                        Integer::valueOf,
                        i -> "group",
                        Integer::compareTo
                );
        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        Map<String, List<Integer>> resultEmpty =
                dataProcessor.<String, Integer>processDataPipeline(
                        Collections.emptyList(),
                        s -> true,
                        Integer::valueOf,
                        i -> "group",
                        Integer::compareTo
                );
        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline performs filtering, mapping, sorting, grouping, distinct and limit per group")
    void testProcessDataPipeline_FunctionalFlowWithLimitAndDistinct() {
        List<String> data = new ArrayList<>();
        for (int i = 0; i < 200; i++) {
            data.add(String.valueOf(i));
            data.add(String.valueOf(i)); // duplicate to test distinct
        }

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        s -> true,
                        Integer::valueOf,
                        i -> "all",
                        Integer::compareTo
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        List<Integer> list = result.get("all");
        assertNotNull(list);
        assertEquals(100, list.size(), "Should limit to 100 per group after distinct");
        assertEquals(0, list.get(0));
        assertEquals(99, list.get(99));
        assertEquals(new HashSet<>(list).size(), list.size(), "List should be distinct");
    }

    @Test
    @DisplayName("processDataPipeline uses provided Predicate/Function/Comparator and groups correctly")
    void testProcessDataPipeline_WithMocks_Verify() {
        List<String> data = Arrays.asList("a", "bb", "ccc");

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        mockFilter,
                        mockTransformer,
                        mockGrouper,
                        mockComparator
                );

        assertNotNull(result);
        assertEquals(2, result.size());
        assertEquals(Collections.singletonList(2), result.get("even"));
        assertEquals(Collections.singletonList(3), result.get("odd"));

    }

    @Test
    @DisplayName("calculateStatistics computes mean, median, quartiles, std dev and no outliers")
    void testCalculateStatistics_Basic() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 6d, 7d, 8d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(4.5, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(5.25), result.getStandardDeviation(), 1e-9);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics detects outliers using IQR method")
    void testCalculateStatistics_WithOutliers() {
        List<Double> values = Arrays.asList(10d, 12d, 12d, 13d, 12d, 11d, 12d, 1000d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(12.0, result.getMedian(), 1e-9);
        assertEquals(11.0, result.getQ1(), 1e-9);
        assertEquals(12.0, result.getQ3(), 1e-9);
        assertEquals(135.25, result.getMean(), 1e-9);
        assertEquals(1, result.getOutliers().size());
        assertEquals(1000.0, result.getOutliers().get(0), 1e-9);
        assertTrue(result.getStandardDeviation() > 300.0 && result.getStandardDeviation() < 400.0);
    }

    @Test
    @DisplayName("calculateStatistics throws on null or empty list")
    void testCalculateStatistics_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel processes keys concurrently and aggregates results")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("k1", "k2", "k3");

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor);

        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("k1"));
        assertEquals(2, result.get("k2"));
        assertEquals(3, result.get("k3"));

    }

    @Test
    @DisplayName("processInParallel propagates exceptions as CompletionException on join")
    void testProcessInParallel_ExceptionPropagation() {
        List<String> keys = Arrays.asList("ok1", "bad", "ok2");

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor);

        assertThrows(CompletionException.class, future::join);

    }

    @Test
    @DisplayName("processInParallel keeps first value on duplicate keys (merge function)")
    void testProcessInParallel_DuplicateKeys_MergeKeepsFirst() {
        List<String> keys = Arrays.asList("a", "a");
        AtomicInteger counter = new AtomicInteger(0);

        Map<String, Integer> result =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor).join();

        assertEquals(1, result.size());
        assertEquals(1, result.get("a")); // first value kept
    }

    @Test
    @DisplayName("findShortestPaths computes correct shortest distances in graph")
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
        graph.put("D", Collections.emptyMap());
        graph.put("E", Collections.emptyMap()); // disconnected

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C"));
        assertEquals(4, distances.get("D"));
        assertEquals(Integer.MAX_VALUE, distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths throws for null graph or missing start node")
    void testFindShortestPaths_Invalid() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("B", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown prevents further parallel task submission")
    void testShutdown_PreventsFurtherParallelSubmission() {
        dataProcessor.shutdown();

        List<String> keys = Collections.singletonList("x");
        assertThrows(RejectedExecutionException.class,
                () -> dataProcessor.<Integer>processInParallel(keys, k -> 1));
    }
}