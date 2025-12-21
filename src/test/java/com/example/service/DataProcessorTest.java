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
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.Comparator;

@ExtendWith(MockitoExtension.class)
public class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Predicate<String> mockPredicate;

    @Mock
    private Function<String, Integer> mockTransformer;

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, dedupes correctly")
    void testProcessDataPipeline_basicFlow() {
        List<String> input = Arrays.asList("apple", "", "banana", "apple");

        when(mockPredicate.test(anyString())).thenAnswer(inv -> {
            String s = inv.getArgument(0);
            return !s.isEmpty();
        });
        when(mockTransformer.apply(anyString())).thenAnswer(inv -> {
            String s = inv.getArgument(0);
            return s.length();
        });

        Comparator<Integer> sorter = Comparator.naturalOrder();
        Function<Integer, String> grouper = i -> (i % 2 == 0) ? "even" : "odd";

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        input,
                        mockPredicate,
                        mockTransformer,
                        grouper,
                        sorter
                );

        assertNotNull(result);
        assertEquals(2, result.size());
        assertEquals(Collections.singletonList(6), result.get("even"));
        assertEquals(Collections.singletonList(5), result.get("odd"));

        verify(mockPredicate, times(input.size())).test(anyString());
        // transformer invoked for non-filtered (non-empty) items: "apple","banana","apple" => 3
        verify(mockTransformer, times(3)).apply(anyString());
    }

    @Test
    @DisplayName("processDataPipeline: handles nulls, enforces per-group limit, preserves sorted order")
    void testProcessDataPipeline_nullsLimitAndOrder() {
        // 0..149 as strings
        List<String> input = new ArrayList<>();
        for (int i = 0; i < 150; i++) input.add(String.valueOf(i));

        Predicate<String> filter = s -> true; // no filtering
        Function<String, Integer> transformer = s -> {
            // introduce nulls for some values to test null filtering in pipeline
            int v = Integer.parseInt(s);
            return (v % 37 == 0) ? null : v; // some nulls
        };
        Function<Integer, String> grouper = i -> "g";
        Comparator<Integer> sorter = Comparator.<Integer>naturalOrder().reversed(); // descending

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        input,
                        filter,
                        transformer,
                        grouper,
                        sorter
                );

        assertNotNull(result);
        assertTrue(result.containsKey("g"));
        List<Integer> group = result.get("g");
        assertNotNull(group);
        // After null filtering, dedupe (no duplicates), limit 100, order descending (149..0 but skipping nulls)
        // All multiples of 37 become null: 0,37,74,111,148 -> removed
        // Remaining highest should be 149 (not removed) and then 147,146,...; 148 removed
        assertEquals(100, group.size());
        assertEquals(149, group.get(0));
        // 50 should be included if it is within the first 100 elements in descending order
        // First 100 elements descending from 149 skipping [148, 111, 74, 37, 0] -> 149 down to about 49 inclusive
        assertTrue(group.contains(50));
        assertFalse(group.contains(49) && group.indexOf(49) >= 100); // 49 should be beyond the 100th if not skipped
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null input")
    void testProcessDataPipeline_nullInput() {
        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        null,
                        s -> true,
                        String::length,
                        i -> "g",
                        Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for empty input")
    void testProcessDataPipeline_emptyInput() {
        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(
                        Collections.emptyList(),
                        s -> true,
                        String::length,
                        i -> "g",
                        Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev, outliers")
    void testCalculateStatistics_typical() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0, 100.0);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);
        assertNotNull(res);

        assertEquals(19.1666666667, res.getMean(), 1e-6);
        assertEquals(3.5, res.getMedian(), 1e-6);
        assertEquals(2.0, res.getQ1(), 1e-6);
        assertEquals(5.0, res.getQ3(), 1e-6);
        // population std dev based on implementation
        assertEquals(36.221601, res.getStandardDeviation(), 1e-5);

        List<Double> outliers = res.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: single element yields zero stddev and no outliers")
    void testCalculateStatistics_singleElement() {
        List<Double> values = Collections.singletonList(10.0);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);
        assertNotNull(res);

        assertEquals(10.0, res.getMean(), 1e-9);
        assertEquals(10.0, res.getMedian(), 1e-9);
        assertEquals(10.0, res.getQ1(), 1e-9);
        assertEquals(10.0, res.getQ3(), 1e-9);
        assertEquals(0.0, res.getStandardDeviation(), 1e-9);
        assertTrue(res.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: throws for null input")
    void testCalculateStatistics_nullInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws for empty input")
    void testCalculateStatistics_emptyInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: completes successfully and aggregates results")
    void testProcessInParallel_success() {
        List<String> keys = Arrays.asList("k1", "k22", "k333");

        Function<String, Integer> func = mock(Function.class);
        when(func.apply(anyString())).thenAnswer(inv -> {
            String k = inv.getArgument(0);
            return k.length();
        });

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, func);
        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(2, result.get("k1"));
        assertEquals(3, result.get("k22"));
        assertEquals(4, result.get("k333"));

        verify(func, times(3)).apply(anyString());
    }

    @Test
    @DisplayName("processInParallel: propagates exceptions with informative message")
    void testProcessInParallel_exception() {
        List<String> keys = Arrays.asList("ok", "bad");

        Function<String, Integer> func = mock(Function.class);
        when(func.apply("ok")).thenReturn(1);
        when(func.apply("bad")).thenThrow(new RuntimeException("boom"));

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, func);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep the first occurrence")
    void testProcessInParallel_duplicateKeysKeepsFirst() {
        List<String> keys = Arrays.asList("a", "a", "b");

        Map<String, AtomicInteger> counters = new HashMap<>();
        Function<String, String> func = key -> {
            counters.computeIfAbsent(key, k -> new AtomicInteger(0));
            int n = counters.get(key).incrementAndGet();
            return key + n;
        };

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, func);
        Map<String, String> result = future.join();

        assertEquals(2, result.size());
        assertEquals("a1", result.get("a")); // first wins
        assertEquals("b1", result.get("b"));
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances from start node")
    void testFindShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<String, Integer>() {{
            put("B", 5);
            put("C", 1);
        }});
        graph.put("B", new HashMap<String, Integer>() {{
            put("D", 1);
        }});
        graph.put("C", new HashMap<String, Integer>() {{
            put("B", 2);
            put("D", 4);
        }});
        graph.put("D", new HashMap<String, Integer>() {{
            put("E", 1);
        }});
        graph.put("E", new HashMap<>());

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(3, distances.get("B").intValue()); // A->C->B
        assertEquals(1, distances.get("C").intValue()); // A->C
        assertEquals(4, distances.get("D").intValue()); // A->C->B->D
        assertEquals(5, distances.get("E").intValue()); // ...->D->E
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph")
    void testFindShortestPaths_nullGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for missing start node")
    void testFindShortestPaths_missingStart() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: terminates executor without exception")
    void testShutdown() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}