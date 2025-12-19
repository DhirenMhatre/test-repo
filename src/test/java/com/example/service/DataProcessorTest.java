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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.Comparator;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Predicate<String> stringFilter;

    @Mock
    private Function<String, Integer> stringToIntTransformer;

    @Mock
    private Comparator<Integer> intComparator;

    @BeforeEach
    void setUp() {
        // Default comparator behavior: natural order
        when(intComparator.compare(anyInt(), anyInt()))
                .thenAnswer(inv -> Integer.compare((Integer) inv.getArgument(0), (Integer) inv.getArgument(1)));
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: basic filter, map, sort, group and dedup")
    void testProcessDataPipeline_basicTransformationAndGrouping() {
        List<String> data = Arrays.asList("a", "bb", "ccc", "dd");

        when(stringFilter.test(anyString())).thenReturn(true);
        when(stringToIntTransformer.apply(anyString()))
                .thenAnswer(inv -> ((String) inv.getArgument(0)).length());

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        stringFilter,
                        stringToIntTransformer,
                        r -> (r % 2 == 0) ? "even" : "odd",
                        intComparator
                );

        assertNotNull(result);
        assertTrue(result.containsKey("even"));
        assertTrue(result.containsKey("odd"));
        assertEquals(Arrays.asList(1, 3), result.get("odd")); // sorted and distinct
        assertEquals(Collections.singletonList(2), result.get("even")); // dedup applied to [2,2]

        verify(stringFilter, times(4)).test(anyString());
        verify(stringToIntTransformer, times(4)).apply(anyString());
        verify(intComparator, atLeast(1)).compare(anyInt(), anyInt());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_nullOrEmpty() {
        Map<String, List<Integer>> resultNull =
                dataProcessor.<String, Integer>processDataPipeline(
                        null,
                        s -> true,
                        String::length,
                        r -> "all",
                        Integer::compareTo
                );
        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        Map<String, List<Integer>> resultEmpty =
                dataProcessor.<String, Integer>processDataPipeline(
                        Collections.emptyList(),
                        s -> true,
                        String::length,
                        r -> "all",
                        Integer::compareTo
                );
        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: respects filter and removes nulls from transformer")
    void testProcessDataPipeline_filtersAndNulls() {
        List<String> data = Arrays.asList("aa", "x", "bb", "null");

        when(stringFilter.test(anyString()))
                .thenAnswer(inv -> {
                    String s = inv.getArgument(0);
                    return s != null && !s.equals("x");
                });

        when(stringToIntTransformer.apply(anyString()))
                .thenAnswer(inv -> {
                    String s = inv.getArgument(0);
                    if ("null".equals(s)) return null; // simulate nulls removed by pipeline
                    return s.length();
                });

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        stringFilter,
                        stringToIntTransformer,
                        r -> "all",
                        intComparator
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertTrue(result.containsKey("all"));
        assertEquals(Collections.singletonList(2), result.get("all"));

        verify(stringFilter, times(4)).test(anyString());
        verify(stringToIntTransformer, times(3)).apply(anyString()); // "x" filtered out, so not applied
    }

    @Test
    @DisplayName("processDataPipeline: enforces limit of 100 items per group after distinct")
    void testProcessDataPipeline_limitPerGroup() {
        List<String> data = new ArrayList<>();
        for (int i = 0; i <= 200; i++) {
            data.add(String.valueOf(i));
        }

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        data,
                        s -> true,
                        Integer::valueOf,
                        r -> "all",
                        Integer::compareTo
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        List<Integer> group = result.get("all");
        assertNotNull(group);
        assertEquals(100, group.size());
        for (int i = 0; i < 100; i++) {
            assertEquals(i, group.get(i));
        }
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev, and outliers")
    void testCalculateStatistics_basic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(19.1666666667, result.getMean(), 1e-6);
        assertEquals(3.5, result.getMedian(), 1e-6);
        assertEquals(2.0, result.getQ1(), 1e-6);
        assertEquals(5.0, result.getQ3(), 1e-6);
        // Population standard deviation as implemented in DataProcessor
        assertEquals(36.176, result.getStandardDeviation(), 0.05);
        assertEquals(Collections.singletonList(100.0), result.getOutliers());

        // Ensure outliers list is unmodifiable
        assertThrows(UnsupportedOperationException.class, () -> result.getOutliers().add(1.0));
    }

    @Test
    @DisplayName("calculateStatistics: throws on null or empty input")
    void testCalculateStatistics_invalidInputThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes all keys and aggregates results")
    void testProcessInParallel_success() {
        List<String> keys = Arrays.asList("a", "b", "c");
        Function<String, String> processor = String::toUpperCase;

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, processor);
        Map<String, String> result = future.join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep first result (merge retains existing)")
    void testProcessInParallel_duplicateKeysFirstWins() {
        List<String> keys = Arrays.asList("dup", "dup");
        AtomicInteger counter = new AtomicInteger(0);
        Function<String, Integer> processor = k -> counter.incrementAndGet();

        Map<String, Integer> result = dataProcessor.processInParallel(keys, processor).join();

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(1, result.get("dup")); // first result retained
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when any task fails")
    void testProcessInParallel_exception() {
        List<String> keys = Arrays.asList("ok", "bad", "ok2");
        Function<String, Integer> processor = k -> {
            if ("bad".equals(k)) throw new IllegalStateException("boom");
            return k.length();
        };

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, processor);

        CompletionException ce = assertThrows(CompletionException.class, future::join);
        assertNotNull(ce.getCause());
        assertTrue(ce.getCause() instanceof RuntimeException);
        assertTrue(ce.getCause().getMessage().contains("Processing failed for key: bad"));
        assertNotNull(ce.getCause().getCause());
        assertTrue(ce.getCause().getCause() instanceof IllegalStateException);
        assertEquals("boom", ce.getCause().getCause().getMessage());
    }

    @Test
    @DisplayName("findShortestPaths: computes distances with Dijkstra-like algorithm including unreachable nodes")
    void testFindShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", mapOf(entry("B", 1), entry("C", 4)));
        graph.put("B", mapOf(entry("C", 2), entry("D", 5)));
        graph.put("C", mapOf(entry("D", 1)));
        graph.put("D", mapOf(entry("E", 3)));
        graph.put("E", Collections.emptyMap());
        graph.put("Z", Collections.emptyMap()); // disconnected

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C")); // A->B->C
        assertEquals(4, (int) distances.get("D")); // A->B->C->D
        assertEquals(7, (int) distances.get("E")); // ...->D->E
        assertEquals(Integer.MAX_VALUE, (int) distances.get("Z")); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void testFindShortestPaths_invalidGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "X"));
    }

    @Test
    @DisplayName("shutdown: is idempotent and does not throw when called multiple times")
    void testShutdown_isIdempotent() {
        assertDoesNotThrow(() -> {
            dataProcessor.shutdown();
            dataProcessor.shutdown();
        });
    }

    // Helpers
    private static <K, V> Map<K, V> mapOf(Map.Entry<K, V>... entries) {
        Map<K, V> map = new HashMap<>();
        for (Map.Entry<K, V> e : entries) {
            map.put(e.getKey(), e.getValue());
        }
        return map;
    }

    private static <K, V> Map.Entry<K, V> entry(K k, V v) {
        return new AbstractMap.SimpleEntry<>(k, v);
    }
}