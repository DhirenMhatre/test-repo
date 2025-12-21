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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline - basic positive flow with transform, sort, group, distinct")
    void testProcessDataPipeline_basic() {
        List<Integer> data = Arrays.asList(3, 1, 2, 2, 5, -1, 3);
        Predicate<Integer> filter = n -> n > 0;
        Function<Integer, Integer> transformer = n -> n * 2;
        Function<Integer, String> grouper = r -> (r % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertTrue(result.containsKey("even"));

        List<Integer> expected = Arrays.asList(2, 4, 6, 10);
        assertEquals(expected, result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline - uses mocks and filters out null transformed results")
    void testProcessDataPipeline_withMocksAndNulls() {
        @SuppressWarnings("unchecked")
        Predicate<Integer> mockFilter = mock(Predicate.class);
        @SuppressWarnings("unchecked")
        Function<Integer, String> mockTransformer = mock(Function.class);
        @SuppressWarnings("unchecked")
        Function<String, String> mockGrouper = mock(Function.class);

        List<Integer> data = Arrays.asList(1, 2, 3);

        when(mockFilter.test(anyInt())).thenReturn(true);
        when(mockTransformer.apply(1)).thenReturn("v1");
        when(mockTransformer.apply(2)).thenReturn(null);
        when(mockTransformer.apply(3)).thenReturn("v3");
        when(mockGrouper.apply(anyString())).thenReturn("group");

        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.<Integer, String>processDataPipeline(
                data, mockFilter, mockTransformer, mockGrouper, sorter
        );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertTrue(result.containsKey("group"));
        assertEquals(Arrays.asList("v1", "v3"), result.get("group"));

        verify(mockFilter, times(3)).test(anyInt());
        verify(mockTransformer, times(3)).apply(anyInt());
        verify(mockGrouper, times(2)).apply(anyString());
    }

    @Test
    @DisplayName("processDataPipeline - returns empty map for null or empty data")
    void testProcessDataPipeline_nullOrEmpty() {
        Predicate<Integer> filter = n -> true;
        Function<Integer, Integer> transformer = n -> n;
        Function<Integer, String> grouper = r -> "g";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> resNull = dataProcessor.<Integer, Integer>processDataPipeline(
                null, filter, transformer, grouper, sorter
        );
        Map<String, List<Integer>> resEmpty = dataProcessor.<Integer, Integer>processDataPipeline(
                Collections.emptyList(), filter, transformer, grouper, sorter
        );

        assertNotNull(resNull);
        assertTrue(resNull.isEmpty());
        assertNotNull(resEmpty);
        assertTrue(resEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline - enforces per-group limit of 100 after deduplication")
    void testProcessDataPipeline_groupLimit100() {
        List<Integer> data = IntStream.range(0, 150).boxed().collect(Collectors.toList());
        Predicate<Integer> filter = n -> true;
        Function<Integer, Integer> transformer = n -> n;
        Function<Integer, String> grouper = r -> "G";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertTrue(result.containsKey("G"));
        List<Integer> group = result.get("G");
        assertEquals(100, group.size());
        List<Integer> expectedFirst100 = IntStream.range(0, 100).boxed().collect(Collectors.toList());
        assertEquals(expectedFirst100, group);
    }

    @Test
    @DisplayName("calculateStatistics - computes mean, median, quartiles, stddev, and outliers")
    void testCalculateStatistics_happyPath() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(115.0 / 6.0, result.getMean(), 1e-9);
        assertEquals(3.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(5.0, result.getQ3(), 1e-9);

        // population standard deviation
        double expectedVariance = Arrays.stream(new double[]{1,2,3,4,5,100})
                .map(v -> v - (115.0/6.0))
                .map(d -> d*d)
                .average().orElse(0.0);
        double expectedStd = Math.sqrt(expectedVariance);
        assertEquals(expectedStd, result.getStandardDeviation(), 1e-9);

        List<Double> outliers = result.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999.0));
    }

    @Test
    @DisplayName("calculateStatistics - throws on null or empty input")
    void testCalculateStatistics_invalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel - processes keys concurrently and aggregates results")
    void testProcessInParallel_success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");
        @SuppressWarnings("unchecked")
        Function<String, Integer> mockProcessor = mock(Function.class);

        when(mockProcessor.apply(anyString())).thenAnswer(inv -> ((String) inv.getArgument(0)).length());

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.processInParallel(keys, mockProcessor);

        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));

        verify(mockProcessor, times(1)).apply("a");
        verify(mockProcessor, times(1)).apply("bb");
        verify(mockProcessor, times(1)).apply("ccc");
    }

    @Test
    @DisplayName("processInParallel - completes exceptionally when a task fails")
    void testProcessInParallel_exceptionPropagation() {
        List<String> keys = Arrays.asList("ok", "fail");
        @SuppressWarnings("unchecked")
        Function<String, String> mockProcessor = mock(Function.class);

        when(mockProcessor.apply("ok")).thenReturn("OK");
        when(mockProcessor.apply("fail")).thenThrow(new IllegalStateException("boom"));

        CompletableFuture<Map<String, String>> future =
                dataProcessor.processInParallel(keys, mockProcessor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: fail"));
    }

    @Test
    @DisplayName("processInParallel - duplicate keys keep first value (merge uses existing)")
    void testProcessInParallel_duplicateKeysFirstWins() {
        List<String> keys = Arrays.asList("x", "x");
        AtomicInteger counter = new AtomicInteger(0);
        Function<String, Integer> processor = k -> counter.incrementAndGet();

        Map<String, Integer> result = dataProcessor.processInParallel(keys, processor).join();

        assertEquals(1, result.size());
        assertTrue(result.containsKey("x"));
        assertEquals(1, result.get("x")); // first value retained
    }

    @Test
    @DisplayName("findShortestPaths - computes minimal distances (Dijkstra-like)")
    void testFindShortestPaths_basic() {
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
        assertEquals(4, distances.size());
    }

    @Test
    @DisplayName("findShortestPaths - throws on invalid graph or missing start node")
    void testFindShortestPaths_invalidArgs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("B", Map.of("A", 1));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown - after shutdown, submitting new tasks via processInParallel completes exceptionally")
    void testShutdown_behavior() {
        DataProcessor dp = new DataProcessor();
        dp.shutdown();

        CompletableFuture<Map<String, Integer>> future =
                dp.processInParallel(Collections.singletonList("k"), k -> 1);

        assertThrows(CompletionException.class, future::join);
    }
}