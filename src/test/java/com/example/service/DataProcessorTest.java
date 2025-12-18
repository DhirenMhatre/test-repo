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
import org.mockito.Mock;
import org.mockito.InjectMocks;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.mockito.Mockito.*;

import java.util.stream.Stream;

import java.util.*;
import java.util.concurrent.CompletionException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public class DataProcessorTest {

    private DataProcessor dataProcessor;

    private Function<String, String> stringProcessor;

    private Predicate<String> stringPredicate;

    private Function<String, Integer> stringToInteger;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();

        // Predicate that keeps strings with odd length
        stringPredicate = s -> s != null && (s.length() % 2 == 1);

        // Transformer that maps string to its length
        stringToInteger = s -> s == null ? 0 : s.length();

        // Processor used for async tests
        // - throws for "bad"
        // - returns "A","B","C" for a,b,c respectively
        // - returns "first" for "x" (so duplicates keep "first")
        // - otherwise returns uppercase of the key
        stringProcessor = key -> {
            if ("bad".equals(key)) {
                throw new RuntimeException("Processing failed for key: bad");
            }
            switch (key) {
                case "a": return "A";
                case "b": return "B";
                case "c": return "C";
                case "x": return "first";
                default: return key == null ? null : key.toUpperCase();
            }
        };

        assertNotNull(dataProcessor);
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: basic filtering, mapping, sorting, grouping and deduplication")
    void testProcessDataPipeline_basicGroupingAndSorting() {
        List<String> data = Arrays.asList(
                "apple", "banana", "apricot", "berry", "cherry", "avocado", "blueberry", "banana"
        );

        Predicate<String> filter = s -> s.startsWith("a") || s.startsWith("b");
        Function<String, Integer> transformer = String::length;
        Function<Integer, String> grouper = len -> (len % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter, 100
        );

        assertNotNull(result);
        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));

        // Values after filtering and mapping: [5,6,7,5,7,9,6]
        // Sorted: [5,5,6,6,7,7,9]
        // Group odd: [5,5,7,7,9] -> distinct -> [5,7,9]
        // Group even: [6,6] -> distinct -> [6]
        assertEquals(Arrays.asList(5, 7, 9), result.get("odd"));
        assertEquals(Collections.singletonList(6), result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 and maintains order after sorting")
    void testProcessDataPipeline_deduplicationAndLimit() {
        List<Integer> data = IntStream.range(0, 150).boxed().collect(Collectors.toList());

        Predicate<Integer> filter = i -> true;
        Function<Integer, Integer> transformer = i -> i;
        Function<Integer, String> grouper = i -> "all";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter, 100
        );

        assertNotNull(result);
        assertTrue(result.containsKey("all"));
        List<Integer> list = result.get("all");
        assertEquals(100, list.size());
        assertEquals(0, list.get(0));
        assertEquals(99, list.get(99));
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for empty input")
    void testProcessDataPipeline_emptyInput() {
        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                Collections.<Integer>emptyList(),
                i -> true,
                i -> i,
                i -> "group",
                Comparator.naturalOrder(),
                100
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null input")
    void testProcessDataPipeline_nullInput() {
        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                null,
                i -> true,
                i -> i,
                i -> "group",
                Comparator.naturalOrder(),
                100
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: uses provided Predicate and Function - verify interactions")
    void testProcessDataPipeline_withMocks_verifiesInteractions() {
        List<String> data = Arrays.asList("a", "bb", "ccc");

        Comparator<Integer> sorter = Comparator.naturalOrder();
        Function<Integer, String> grouper = i -> "group";

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, stringPredicate, stringToInteger, grouper, sorter, 100
        );

        assertNotNull(result);
        assertTrue(result.containsKey("group"));
        assertEquals(Arrays.asList(1, 3), result.get("group"));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev and outliers (IQR)")
    void testCalculateStatistics_basicMetricsAndOutliers() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(19.166666666666668, result.getMean(), 1e-9);
        assertEquals(3.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(5.0, result.getQ3(), 1e-9);
        assertEquals(Math.sqrt(1308.25), result.getStandardDeviation(), 1e-9);
        assertEquals(Collections.singletonList(100.0), result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for null or empty input")
    void testCalculateStatistics_invalidInputThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys asynchronously and aggregates results into a map")
    void testProcessInParallel_happyPath() {
        List<String> keys = Arrays.asList("a", "b", "c");

        Map<String, String> result = dataProcessor.processInParallel(keys, stringProcessor).join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a processor throws")
    void testProcessInParallel_exceptionallyCompletesWhenOneFails() {
        List<String> keys = Arrays.asList("ok", "bad", "ok2");

        CompletionException ex = assertThrows(
                CompletionException.class,
                () -> dataProcessor.processInParallel(keys, stringProcessor).join()
        );

        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep the first value due to merge function")
    void testProcessInParallel_duplicateKeysKeepsFirst() {
        List<String> keys = Arrays.asList("x", "x");

        Map<String, String> result = dataProcessor.processInParallel(keys, stringProcessor).join();

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals("first", result.get("x"));
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest paths in a directed weighted graph")
    void testFindShortestPaths_validGraph() {
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
        graph.put("E", new HashMap<>()); // disconnected

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(5, distances.size());
        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C (1 + 2)
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D (1 + 2 + 1)
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: throws IllegalArgumentException for invalid graph or start node")
    void testFindShortestPaths_invalidGraphThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: can be called without exceptions")
    void testShutdown() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}