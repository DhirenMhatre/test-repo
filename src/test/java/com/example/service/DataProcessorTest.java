package com.example.service;

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
import java.util.stream.Collectors;
import java.util.stream.IntStream;

class DataProcessorTest {

    private DataProcessor processor;

    @BeforeEach
    void setUp() {
        processor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        if (processor != null) {
            try {
                processor.shutdown();
            } catch (Exception ignored) {
            }
        }
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, dedups correctly with mocks")
    void testProcessDataPipeline_FullFlowWithMocks() {
        List<String> data = Arrays.asList("a1", "a2", "b2", "b1", "x", "a2");

        Predicate<String> filter = s -> s != null && !s.isEmpty() && Character.isDigit(s.charAt(s.length() - 1)));
        Function<String, Integer> transformer = s -> {
            if (s == null || s.isEmpty()) return null;
            char c = s.charAt(s.length() - 1);
            return Character.isDigit(c) ? Character.getNumericValue(c) : null;
        };
        Function<Integer, String> grouper = v -> (v % 2 == 0) ? "even" : "odd";

        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                data,
                filter,
                transformer,
                grouper,
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertEquals(2, result.size());
        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));
        assertEquals(Collections.singletonList(1), result.get("odd"));
        assertEquals(Collections.singletonList(2), result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline: applies per-group limit of 100 after distinct")
    void testProcessDataPipeline_AppliesGroupLimit() {
        List<String> data = IntStream.range(0, 200).mapToObj(i -> "v" + i).collect(Collectors.toList());

        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                data,
                s -> true,
                s -> Integer.parseInt(s.substring(1)),
                i -> "group",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertEquals(1, result.size());
        List<Integer> group = result.get("group");
        assertNotNull(group);
        assertEquals(100, group.size());
        List<Integer> expected = IntStream.range(0, 100).boxed().collect(Collectors.toList());
        assertEquals(expected, group);
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null input")
    void testProcessDataPipeline_NullInput() {
        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                s -> s.length(),
                Object::toString,
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for empty input")
    void testProcessDataPipeline_EmptyInput() {
        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                s -> s.length(),
                Object::toString,
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stdDev, and detects outliers")
    void testCalculateStatistics_Basic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = processor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(18.6666666667, result.getMean(), 1e-6);
        assertEquals(2.5, result.getMedian(), 1e-6);
        assertEquals(2.0, result.getQ1(), 1e-6);
        assertEquals(4.0, result.getQ3(), 1e-6);
        assertEquals(36.389, result.getStandardDeviation(), 1e-3);
        assertEquals(Collections.singletonList(100.0), result.getOutliers());

        assertThrows(UnsupportedOperationException.class, () -> result.getOutliers().add(5.0));
    }

    @Test
    @DisplayName("calculateStatistics: single element statistics")
    void testCalculateStatistics_SingleElement() {
        List<Double> values = Collections.singletonList(42.0);

        DataProcessor.StatisticalResult result = processor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(42.0, result.getMean(), 1e-9);
        assertEquals(42.0, result.getMedian(), 1e-9);
        assertEquals(42.0, result.getQ1(), 1e-9);
        assertEquals(42.0, result.getQ3(), 1e-9);
        assertEquals(0.0, result.getStandardDeviation(), 1e-12);
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: throws on null input")
    void testCalculateStatistics_NullInput() {
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws on empty input")
    void testCalculateStatistics_EmptyInput() {
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: aggregates results into a map successfully")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("alpha", "beta", "gamma");

        Function<String, Integer> lengthFunc = s -> s.length();

        CompletableFuture<Map<String, Integer>> future =
                processor.<Integer>processInParallel(keys, lengthFunc);

        Map<String, Integer> result = future.join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(Integer.valueOf(5), result.get("alpha"));
        assertEquals(Integer.valueOf(4), result.get("beta"));
        assertEquals(Integer.valueOf(5), result.get("gamma"));
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when processor throws")
    void testProcessInParallel_Failure() {
        List<String> keys = Arrays.asList("a", "b", "c");

        Function<String, Integer> func = s -> {
            if ("b".equals(s)) {
                throw new RuntimeException("Processing failed for key: " + s);
            }
            return s.length();
        };

        CompletableFuture<Map<String, Integer>> future =
                processor.<Integer>processInParallel(keys, func);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: b"));
    }

    @Test
    @DisplayName("findShortestPaths: computes correct shortest distances (including unreachable nodes)")
    void testFindShortestPaths_BasicGraph() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("C", new HashMap<>());
        graph.put("D", new HashMap<>());
        graph.put("E", new HashMap<>());

        graph.get("A").put("B", 1);
        graph.get("A").put("C", 4);
        graph.get("B").put("C", 2);
        graph.get("B").put("D", 5);
        graph.get("C").put("D", 1);

        Map<String, Integer> distances = processor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C"));
        assertEquals(4, distances.get("D"));
        assertEquals(Integer.MAX_VALUE, distances.get("E"));
        assertEquals(5, distances.size());
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_InvalidInput() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());

        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(null, "A"));
        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: should not throw")
    void testShutdown_NoException() {
        assertDoesNotThrow(() -> processor.shutdown());
    }
}