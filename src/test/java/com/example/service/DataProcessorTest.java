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
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Predicate<String> mockFilter;

    @Mock
    private Function<String, Integer> mockTransformer;

    @Mock
    private Function<Integer, String> mockGrouper;

    @Mock
    private Comparator<Integer> mockComparator;

    @Mock
    private Function<String, Integer> mockAsyncProcessor;

    @BeforeEach
    void setUp() {
        // DataProcessor is created by @InjectMocks
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
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

        when(mockFilter.test("a")).thenReturn(false);
        when(mockFilter.test("bb")).thenReturn(true);
        when(mockFilter.test("ccc")).thenReturn(true);

        when(mockTransformer.apply("bb")).thenReturn(2);
        when(mockTransformer.apply("ccc")).thenReturn(3);

        when(mockGrouper.apply(2)).thenReturn("even");
        when(mockGrouper.apply(3)).thenReturn("odd");

        when(mockComparator.compare(anyInt(), anyInt()))
                .thenAnswer(inv -> Integer.compare(inv.getArgument(0), inv.getArgument(1)));

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

        verify(mockFilter, times(3)).test(anyString());
        verify(mockTransformer, times(2)).apply(anyString());
        verify(mockGrouper, times(2)).apply(anyInt());
        verify(mockComparator, atLeastOnce()).compare(anyInt(), anyInt());
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

        when(mockAsyncProcessor.apply("k1")).thenReturn(1);
        when(mockAsyncProcessor.apply("k2")).thenReturn(2);
        when(mockAsyncProcessor.apply("k3")).thenReturn(3);

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor);

        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("k1"));
        assertEquals(2, result.get("k2"));
        assertEquals(3, result.get("k3"));

        verify(mockAsyncProcessor).apply("k1");
        verify(mockAsyncProcessor).apply("k2");
        verify(mockAsyncProcessor).apply("k3");
    }

    @Test
    @DisplayName("processInParallel propagates exceptions as CompletionException on join")
    void testProcessInParallel_ExceptionPropagation() {
        List<String> keys = Arrays.asList("ok1", "bad", "ok2");

        when(mockAsyncProcessor.apply("ok1")).thenReturn(10);
        when(mockAsyncProcessor.apply("bad")).thenThrow(new RuntimeException("Processing error"));
        when(mockAsyncProcessor.apply("ok2")).thenReturn(20);

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor);

        assertThrows(CompletionException.class, future::join);

        verify(mockAsyncProcessor).apply("ok1");
        verify(mockAsyncProcessor).apply("bad");
        verify(mockAsyncProcessor).apply("ok2");
    }

    @Test
    @DisplayName("processInParallel keeps first value on duplicate keys (merge function)")
    void testProcessInParallel_DuplicateKeys_MergeKeepsFirst() {
        List<String> keys = Arrays.asList("a", "a");
        AtomicInteger counter = new AtomicInteger(0);
        when(mockAsyncProcessor.apply(anyString())).thenAnswer(inv -> counter.incrementAndGet());

        Map<String, Integer> result =
                dataProcessor.<Integer>processInParallel(keys, mockAsyncProcessor).join();

        assertEquals(1, result.size());
        assertEquals(1, result.get("a")); // first value kept
        verify(mockAsyncProcessor, times(2)).apply("a");
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