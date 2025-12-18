package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.Comparator;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    private static final double EPS = 1e-9;

    private DataProcessor dataProcessor;

    @Mock
    private Predicate<Integer> intFilter;

    @Mock
    private Function<Integer, String> intToString;

    @Mock
    private Function<String, String> grouper;

    @Mock
    private Function<String, Integer> parallelProcessor;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();

        // Default stubbing for pipeline mocks
        when(intFilter.test(anyInt())).thenReturn(true);
        when(intToString.apply(anyInt())).thenAnswer(inv -> String.valueOf((Integer) inv.getArgument(0)));
        when(grouper.apply(anyString())).thenReturn("G");

        // Default stubbing for parallel processor
        when(parallelProcessor.apply("a")).thenReturn(1);
        when(parallelProcessor.apply("b")).thenReturn(42);
        when(parallelProcessor.apply("ok")).thenReturn(7);
        when(parallelProcessor.apply("ok2")).thenReturn(9);
        when(parallelProcessor.apply("bad")).thenThrow(new RuntimeException("boom"));
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: end-to-end pipeline (filter, map, sort, group, distinct, limit) with real functions")
    void testProcessDataPipeline_BasicFlowIntegration() {
        List<Integer> input = Arrays.asList(1, -1, 2, 3, 2, 3, 4);

        Predicate<Integer> filter = v -> v > 0;
        Function<Integer, String> transformer = String::valueOf;
        Function<String, String> groupByOddEven = s -> (Integer.parseInt(s) % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                input, filter, transformer, groupByOddEven, sorter
        );

        assertEquals(2, result.size());
        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));

        assertEquals(Arrays.asList("1", "3"), result.get("odd"));
        assertEquals(Arrays.asList("2", "4"), result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline: uses mocks, verifies invocations, applies distinct and group limit of 100")
    void testProcessDataPipeline_VerifyMocksAndLimit() {
        List<Integer> data = IntStream.rangeClosed(1, 200).boxed().collect(Collectors.toList());

        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                data,
                intFilter,
                intToString,
                grouper,
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        assertTrue(result.containsKey("G"));
        List<String> group = result.get("G");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(new HashSet<>(group).size(), group.size()); // distinct

        verify(intFilter, atLeastOnce()).test(anyInt());
        verify(intToString, atLeastOnce()).apply(anyInt());
        verify(grouper, atLeastOnce()).apply(anyString());
        verifyNoMoreInteractions(intFilter, intToString, grouper);
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_NullOrEmpty() {
        // Null input
        List<Integer> nullList = null;
        Map<String, List<Integer>> resultNull = dataProcessor.processDataPipeline(
                nullList,
                x -> true,
                x -> x,
                Object::toString,
                Comparator.naturalOrder()
        );
        assertTrue(resultNull.isEmpty());

        // Empty input
        List<Integer> emptyList = Collections.emptyList();
        Map<String, List<Integer>> resultEmpty = dataProcessor.processDataPipeline(
                emptyList,
                x -> true,
                x -> x,
                Object::toString,
                Comparator.naturalOrder()
        );
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev, and outliers (IQR method)")
    void testCalculateStatistics_Computation() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        assertAll(
                () -> assertEquals(22.0, stats.getMean(), EPS),
                () -> assertEquals(3.0, stats.getMedian(), EPS),
                () -> assertEquals(2.0, stats.getQ1(), EPS),
                () -> assertEquals(4.0, stats.getQ3(), EPS),
                () -> {
                    double expectedStd = Math.sqrt(1522.0);
                    assertEquals(expectedStd, stats.getStandardDeviation(), EPS);
                },
                () -> {
                    List<Double> outliers = stats.getOutliers();
                    assertEquals(1, outliers.size());
                    assertEquals(100.0, outliers.get(0), EPS);
                }
        );
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for null or empty lists")
    void testCalculateStatistics_Exceptions() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys asynchronously, merges duplicates preferring first occurrence")
    void testProcessInParallel_SuccessAndDuplicateKeys() {
        List<String> keys = Arrays.asList("a", "b", "a");

        Map<String, Integer> result = dataProcessor.processInParallel(keys, parallelProcessor).join();

        assertEquals(2, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(42, result.get("b"));
    }

    @Test
    @DisplayName("processInParallel: propagates exception when processor fails for a key")
    void testProcessInParallel_ProcessorThrows() {
        List<String> keys = Arrays.asList("ok", "bad", "ok2");

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, parallelProcessor);

        assertThrows(CompletionException.class, future::join);
    }

    @Test
    @DisplayName("processInParallel: fails after shutdown due to rejected execution")
    void testProcessInParallel_AfterShutdown() {
        dataProcessor.shutdown();

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(
                Collections.singletonList("k"),
                k -> 123
        );

        assertThrows(CompletionException.class, future::join);
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest paths in a small weighted graph")
    void testFindShortestPaths_BasicGraph() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 4)));
        graph.put("B", new HashMap<>(Map.of("C", 2, "D", 5)));
        graph.put("C", new HashMap<>(Map.of("D", 1)));
        graph.put("D", new HashMap<>());

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C"));
        assertEquals(4, distances.get("D"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph or invalid start node")
    void testFindShortestPaths_InvalidInputs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    @Test
    @DisplayName("shutdown: can be called multiple times without throwing")
    void testShutdown_Idempotent() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}