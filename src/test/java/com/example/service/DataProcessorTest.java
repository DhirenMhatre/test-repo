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
import java.util.function.Function;
import java.util.function.Predicate;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Predicate<String> stringFilter;

    @Mock
    private Function<String, Integer> stringToInt;

    @Mock
    private Function<String, String> parallelProcessor;

    @BeforeEach
    void setUp() {
        // @InjectMocks will construct DataProcessor via default constructor
        assertNotNull(dataProcessor);
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    // processDataPipeline tests

    @Test
    @DisplayName("processDataPipeline: basic flow with filtering, mapping, sorting, grouping, dedup")
    void testProcessDataPipeline_basicFlow() {
        List<String> data = Arrays.asList("a", "bb", "ccc", "bb", "dddd", "a");

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data,
                s -> s != null && !s.isEmpty(),
                String::length,
                len -> (len % 2 == 0) ? "even" : "odd",
                Comparator.naturalOrder()
        );

        assertEquals(2, result.size());
        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));

        // After sorting globally -> [1,1,2,2,3,4]
        // Group -> odd:[1,1,3] even:[2,2,4]
        // Distinct per group -> odd:[1,3], even:[2,4]
        assertEquals(Arrays.asList(1, 3), result.get("odd"));
        assertEquals(Arrays.asList(2, 4), result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_emptyOrNull() {
        Map<String, List<Integer>> r1 = dataProcessor.<String, Integer>processDataPipeline(
                null, s -> true, String::length, Object::toString, Comparator.naturalOrder());
        Map<String, List<Integer>> r2 = dataProcessor.<String, Integer>processDataPipeline(
                Collections.emptyList(), s -> true, String::length, Object::toString, Comparator.naturalOrder());

        assertTrue(r1.isEmpty());
        assertTrue(r2.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: distinct and limit 100 per group applied after grouping")
    void testProcessDataPipeline_limitAndDistinct() {
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) data.add(i);

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                data,
                i -> true,
                Integer::valueOf,
                r -> "all",
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        List<Integer> group = result.get("all");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
        // Ensure distinct
        Set<Integer> set = new HashSet<>(group);
        assertEquals(100, set.size());
    }

    @Test
    @DisplayName("processDataPipeline: verify filter and transformer invocations with mocks")
    void testProcessDataPipeline_withMocks_verifyBehavior() {
        List<String> data = Arrays.asList("keep", "drop", "alsoDrop");

        when(stringFilter.test("keep")).thenReturn(true);
        when(stringFilter.test("drop")).thenReturn(false);
        when(stringFilter.test("alsoDrop")).thenReturn(false);

        when(stringToInt.apply("keep")).thenReturn(42);

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data,
                stringFilter,
                stringToInt,
                r -> "group",
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        assertEquals(Collections.singletonList(42), result.get("group"));

        verify(stringFilter, times(1)).test("keep");
        verify(stringFilter, times(1)).test("drop");
        verify(stringFilter, times(1)).test("alsoDrop");
        verify(stringToInt, times(1)).apply("keep");
        // Transformer should not be called for filtered-out items
        verify(stringToInt, never()).apply("drop");
        verify(stringToInt, never()).apply("alsoDrop");
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stddev, outliers")
    void testCalculateStatistics_basic() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // Expected with current implementation:
        // sorted: [1,2,3,4,5,100]
        // mean = 115/6 ≈ 19.1666667
        // median = (3 + 4) / 2 = 3.5
        // q1 at ceil(0.25*6)-1 = 1 -> 2
        // q3 at ceil(0.75*6)-1 = 4 -> 5
        // stddev (population) ≈ sqrt(1308.472222...) ≈ 36.173
        assertEquals(19.1666666667, result.getMean(), 1e-9);
        assertEquals(3.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(5.0, result.getQ3(), 1e-9);
        assertEquals(36.173, result.getStandardDeviation(), 1e-2); // tolerance
        assertEquals(Collections.singletonList(100d), result.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for null input")
    void testCalculateStatistics_nullInputThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for empty input")
    void testCalculateStatistics_emptyInputThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("calculateStatistics: outliers list is unmodifiable")
    void testCalculateStatistics_outliersUnmodifiable() {
        List<Double> values = Arrays.asList(10d, 10d, 10d, 10d, 1000d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        List<Double> outliers = result.getOutliers();
        assertFalse(outliers.isEmpty());

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(123.0));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel: processes keys concurrently and keeps first value for duplicate keys")
    void testProcessInParallel_successWithDuplicateKeys() {
        List<String> keys = Arrays.asList("a", "b", "a");

        when(parallelProcessor.apply("a")).thenReturn("A1", "A2");
        when(parallelProcessor.apply("b")).thenReturn("B1");

        CompletableFuture<Map<String, String>> future =
                dataProcessor.processInParallel(keys, parallelProcessor);
        Map<String, String> result = future.join();

        assertEquals(2, result.size());
        assertEquals("A1", result.get("a"));
        assertEquals("B1", result.get("b"));

        verify(parallelProcessor, times(2)).apply("a");
        verify(parallelProcessor, times(1)).apply("b");
    }

    @Test
    @DisplayName("processInParallel: propagates exception as CompletionException on join")
    void testProcessInParallel_exceptionPropagates() {
        List<String> keys = Arrays.asList("ok", "fail");

        Function<String, String> processor = key -> {
            if ("fail".equals(key)) {
                throw new RuntimeException("boom");
            }
            return "OK:" + key;
        };

        CompletableFuture<Map<String, String>> cf = dataProcessor.processInParallel(keys, processor);

        assertThrows(CompletionException.class, cf::join);
    }

    @Test
    @DisplayName("processInParallel: after shutdown, submissions are rejected")
    void testProcessInParallel_afterShutdownThrows() {
        dataProcessor.shutdown();

        List<String> keys = Collections.singletonList("x");
        Function<String, String> processor = s -> s;

        assertThrows(java.util.concurrent.RejectedExecutionException.class,
                () -> dataProcessor.processInParallel(keys, processor));
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths: computes shortest distances in weighted graph")
    void testFindShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("C", new HashMap<>());
        graph.put("D", new HashMap<>());

        graph.get("A").put("B", 1);
        graph.get("A").put("C", 4);
        graph.get("B").put("C", 2);
        graph.get("B").put("D", 5);
        graph.get("C").put("D", 1);

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C")); // A->B->C
        assertEquals(4, distances.get("D")); // A->B->C->D
    }

    @Test
    @DisplayName("findShortestPaths: unreachable nodes remain at Integer.MAX_VALUE")
    void testFindShortestPaths_unreachable() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("E", new HashMap<>()); // unreachable from A

        graph.get("A").put("B", 10);
        // E has no incoming from reachable nodes

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(10, distances.get("B"));
        assertEquals(Integer.MAX_VALUE, distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph")
    void testFindShortestPaths_nullGraphThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "X"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid start node")
    void testFindShortestPaths_invalidStartNodeThrows() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());

        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }
}