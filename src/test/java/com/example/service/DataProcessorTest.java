package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.Arguments;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;

import java.util.stream.Stream;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.Comparator;

class DataProcessorTest {

    private DataProcessor dataProcessor;

    private Function<String, Integer> mockFunction;

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when input list is null or empty")
    void testProcessDataPipelineEmptyOrNull() {
        Map<String, List<Integer>> result1 =
                dataProcessor.<String, Integer>processDataPipeline(null, s -> true, String::length, Object::toString, Comparator.naturalOrder());
        Map<String, List<Integer>> result2 =
                dataProcessor.<String, Integer>processDataPipeline(Collections.emptyList(), s -> true, String::length, Object::toString, Comparator.naturalOrder());

        assertTrue(result1.isEmpty());
        assertTrue(result2.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: applies filter, transformer, null-filter, sort, group, and per-group distinct with limit")
    void testProcessDataPipelineFullFlow() {
        List<String> data = Arrays.asList("apple", "banana", "apricot", "blueberry", "avocado", "banana", "ax");

        Predicate<String> filter = s -> s.startsWith("a") || s.startsWith("b");
        Function<String, Integer> transformer = s -> "ax".equals(s) ? null : s.length();
        Function<Integer, String> grouper = len -> len % 2 == 0 ? "even" : "odd";

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        filter,
                        transformer,
                        grouper,
                        Comparator.naturalOrder()
                );

        // Expect odd: [5,7,9], even: [6]
        assertNotNull(result);
        assertEquals(Arrays.asList(6), result.get("even"));
        assertEquals(Arrays.asList(5, 7, 9), result.get("odd"));
        // Ensure only expected groups present
        assertEquals(new HashSet<>(Arrays.asList("even", "odd")), result.keySet());
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev, and outliers (IQR)")
    void testCalculateStatisticsHappyPath() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 4d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(18.666666666666668, result.getMean(), 1e-9);
        assertEquals(2.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(4.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(1323.8888888888887), result.getStandardDeviation(), 1e-6);
        assertEquals(Collections.singletonList(100.0), result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for null or empty input")
    void testCalculateStatisticsInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult: outliers list is unmodifiable")
    void testStatisticalResultOutliersImmutability() {
        List<Double> values = Arrays.asList(10d, 10d, 10d, 10d, 1000d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        List<Double> outliers = result.getOutliers();
        assertTrue(outliers.contains(1000.0));
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(123.0));
    }

    @Test
    @DisplayName("processInParallel: processes all keys and aggregates results")
    void testProcessInParallelSuccess() throws Exception {
        List<String> keys = Arrays.asList("k1", "k2", "k3");


        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, mockFunction);
        Map<String, Integer> result = future.get();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("k1"));
        assertEquals(2, result.get("k2"));
        assertEquals(3, result.get("k3"));

        verifyNoMoreInteractions(mockFunction);
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when processor throws")
    void testProcessInParallelException() {
        List<String> keys = Arrays.asList("ok1", "bad", "ok2");


        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, mockFunction);

        ExecutionException ex = assertThrows(ExecutionException.class, future::get);
        assertNotNull(ex.getCause());
        // The cause may be a CompletionException with nested RuntimeException
        Throwable cause = ex.getCause();
        Throwable root = cause.getCause() != null ? cause.getCause() : cause;
        assertTrue(root.getMessage().contains("Processing failed for key: bad"));

        verifyNoMoreInteractions(mockFunction);
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest paths correctly including unreachable nodes")
    void testFindShortestPaths() {
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
        graph.put("D", new HashMap<String, Integer>() {{
            put("E", 3);
        }});
        graph.put("E", Collections.emptyMap());
        graph.put("F", Collections.emptyMap()); // unreachable

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C")); // A->B->C
        assertEquals(4, (int) distances.get("D")); // A->B->C->D
        assertEquals(7, (int) distances.get("E")); // ...->D->E
        assertEquals(Integer.MAX_VALUE, (int) distances.get("F")); // unreachable
        assertEquals(6, distances.size());
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or missing start node")
    void testFindShortestPathsInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());

        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: should not throw when called multiple times")
    void testShutdownIdempotent() {
        assertDoesNotThrow(() -> {
            dataProcessor.shutdown();
            dataProcessor.shutdown();
        });
    }
}
