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
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.mockito.Mockito.*;

import java.util.stream.Stream;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    private DataProcessor dataProcessor;

    @Mock
    private Function<String, String> mockProcessor;

    @Mock
    private Predicate<String> mockFilter;

    @Mock
    private Function<String, String> mockTransformer;

    @Mock
    private Function<String, String> mockGrouper;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline - basic grouping, sorting, and deduplication")
    void testProcessDataPipeline_basic() {
        List<String> data = Arrays.asList("b", "a", "c", "a", "d");

        Predicate<String> filter = s -> true;
        Function<String, String> transformer = Function.identity();
        Function<String, String> grouper = s -> s.substring(0, 1);
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertEquals(4, result.size());
        assertEquals(List.of("a"), result.get("a"));
        assertEquals(List.of("b"), result.get("b"));
        assertEquals(List.of("c"), result.get("c"));
        assertEquals(List.of("d"), result.get("d"));
    }

    @Test
    @DisplayName("processDataPipeline - uses mocks, handles nulls from transformer, verifies interactions")
    void testProcessDataPipeline_withMocksAndNulls() {
        List<String> data = Arrays.asList("x", "y", "z");

        when(mockFilter.test(anyString())).thenReturn(true);
        when(mockTransformer.apply(anyString())).thenAnswer(inv -> {
            String s = inv.getArgument(0);
            return "y".equals(s) ? null : s.toUpperCase();
        });
        when(mockGrouper.apply(anyString())).thenReturn("G");

        Comparator<String> sorter = String::compareTo;

        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                data, mockFilter, mockTransformer, mockGrouper, sorter
        );

        assertEquals(1, result.size());
        assertTrue(result.containsKey("G"));
        assertEquals(Arrays.asList("X", "Z"), result.get("G"));

        verify(mockGrouper, times(2)).apply(anyString());
        verifyNoMoreInteractions(mockGrouper);
    }

    @Test
    @DisplayName("processDataPipeline - returns empty map for empty input")
    void testProcessDataPipeline_empty() {
        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                Collections.<String>emptyList(),
                s -> true,
                Function.identity(),
                s -> "G",
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline - returns empty map for null input")
    void testProcessDataPipeline_null() {
        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                null,
                s -> true,
                Function.identity(),
                s -> "G",
                Comparator.naturalOrder()
        );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline - enforces per-group limit of 100 after dedupe")
    void testProcessDataPipeline_groupLimit100() {
        // 150 distinct items that all map to group "G", sorted lexicographically via zero-padding
        List<Integer> ints = new ArrayList<>();
        for (int i = 0; i < 150; i++) ints.add(i);

        List<Integer> data = ints;
        Predicate<Integer> filter = i -> true;
        Function<Integer, String> transformer = i -> String.format("V%03d", i);
        Function<String, String> grouper = s -> "G";
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertEquals(1, result.size());
        List<String> group = result.get("G");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals("V000", group.get(0));
        assertEquals("V099", group.get(99));
    }

    @Test
    @DisplayName("calculateStatistics - basic stats on odd-sized list with no outliers")
    void testCalculateStatistics_basic() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        assertEquals(3.0, stats.getMean(), 1e-9);
        assertEquals(3.0, stats.getMedian(), 1e-9);
        assertEquals(2.0, stats.getQ1(), 1e-9);
        assertEquals(4.0, stats.getQ3(), 1e-9);
        assertEquals(Math.sqrt(2.0), stats.getStandardDeviation(), 1e-9);
        assertTrue(stats.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics - detects outliers and computes population std dev")
    void testCalculateStatistics_withOutlier() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        // Known quartiles per implementation
        assertEquals(2.0, stats.getQ1(), 1e-9);
        assertEquals(5.0, stats.getQ3(), 1e-9);
        assertEquals(3.5, stats.getMedian(), 1e-9);
        assertEquals(115.0 / 6.0, stats.getMean(), 1e-9);
        // Standard deviation computed as population std dev
        double mean = values.stream().mapToDouble(Double::doubleValue).average().orElseThrow();
        double variance = values.stream().mapToDouble(v -> Math.pow(v - mean, 2)).average().orElseThrow();
        double expectedStdDev = Math.sqrt(variance);
        assertEquals(expectedStdDev, stats.getStandardDeviation(), 1e-9);

        assertEquals(1, stats.getOutliers().size());
        assertEquals(100.0, stats.getOutliers().get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics - throws on null input")
    void testCalculateStatistics_nullThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics - throws on empty input")
    void testCalculateStatistics_emptyThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult - outliers list is unmodifiable")
    void testStatisticalResult_outliersUnmodifiable() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);
        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);
        List<Double> outliers = stats.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(200d));
    }

    @Test
    @DisplayName("processInParallel - aggregates all results successfully and invokes processor for each key")
    void testProcessInParallel_success() throws Exception {
        when(mockProcessor.apply(anyString())).thenAnswer(inv -> inv.getArgument(0) + "-v");

        List<String> keys = Arrays.asList("a", "b", "c");
        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, mockProcessor);
        Map<String, String> result = future.get(5, TimeUnit.SECONDS);

        assertEquals(3, result.size());
        assertEquals("a-v", result.get("a"));
        assertEquals("b-v", result.get("b"));
        assertEquals("c-v", result.get("c"));

        verify(mockProcessor, times(3)).apply(anyString());
        verifyNoMoreInteractions(mockProcessor);
    }

    @Test
    @DisplayName("processInParallel - duplicate keys keep the first computed value")
    void testProcessInParallel_duplicateKeys() throws Exception {
        AtomicInteger counter = new AtomicInteger();
        Function<String, String> processor = k -> k + counter.getAndIncrement();

        List<String> keys = Arrays.asList("x", "x");
        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, processor);
        Map<String, String> result = future.get(5, TimeUnit.SECONDS);

        assertEquals(1, result.size());
        assertEquals("x0", result.get("x"));
    }

    @Test
    @DisplayName("processInParallel - exception in processor propagates as ExecutionException")
    void testProcessInParallel_exception() {
        when(mockProcessor.apply("ok")).thenReturn("ok-v");
        when(mockProcessor.apply("bad")).thenThrow(new RuntimeException("Processing failed for key: bad"));

        List<String> keys = Arrays.asList("ok", "bad");
        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, mockProcessor);

        ExecutionException ex = assertThrows(ExecutionException.class, future::get);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("findShortestPaths - computes correct shortest distances")
    void testFindShortestPaths_validGraph() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 4)));
        graph.put("B", new HashMap<>(Map.of("C", 2, "D", 5)));
        graph.put("C", new HashMap<>(Map.of("D", 1)));
        graph.put("D", new HashMap<>());

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C")); // A->B->C
        assertEquals(4, distances.get("D")); // A->B->C->D
    }

    @Test
    @DisplayName("findShortestPaths - throws for null graph")
    void testFindShortestPaths_nullGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths - throws for missing start node")
    void testFindShortestPaths_missingStart() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Map.of("Y", 2));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown - idempotent and does not throw")
    void testShutdown_idempotent() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}