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
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.function.Predicate;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    private DataProcessor dataProcessor;

    @Mock
    private Predicate<String> stringPredicate;

    @Mock
    private Function<String, Integer> stringToInt;

    @Mock
    private Function<Integer, String> intToGroup;

    private Function<String, String> parallelProcessorString;

    private Function<String, Integer> parallelProcessorInt;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();

        // Default stubbing for mocked pipeline functions
        when(stringPredicate.test(anyString())).thenReturn(true);
        when(stringToInt.apply(anyString())).thenReturn(42);
        when(intToGroup.apply(anyInt())).thenReturn("grp");

        // Parallel processors for tests
        parallelProcessorString = key -> key + "1";
        parallelProcessorInt = key -> {
            if ("x".equals(key)) {
                throw new IllegalStateException("boom");
            }
            return 1;
        };
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline - returns empty map for null or empty input")
    void testProcessDataPipeline_emptyOrNull() {
        Map<String, List<Integer>> resultNull = dataProcessor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                String::length,
                i -> i % 2 == 0 ? "even" : "odd",
                Comparator.naturalOrder()
        );
        assertTrue(resultNull.isEmpty());

        Map<String, List<Integer>> resultEmpty = dataProcessor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                String::length,
                i -> i % 2 == 0 ? "even" : "odd",
                Comparator.naturalOrder()
        );
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline - transforms, filters, sorts, groups, deduplicates")
    void testProcessDataPipeline_pipelineBehavior() {
        List<String> data = Arrays.asList("aa", "bbbb", "ccc", "dddd", "aa");
        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data,
                s -> s.length() >= 2,
                String::length,
                i -> i % 2 == 0 ? "even" : "odd",
                Comparator.naturalOrder()
        );

        assertEquals(2, result.size());

        List<Integer> even = result.get("even");
        List<Integer> odd = result.get("odd");

        assertNotNull(even);
        assertNotNull(odd);

        // Deduplicated values
        assertEquals(Arrays.asList(2, 4), even);
        assertEquals(Collections.singletonList(3), odd);
    }

    @Test
    @DisplayName("processDataPipeline - enforces limit of 100 elements per group after distinct")
    void testProcessDataPipeline_limitPerGroup() {
        List<Integer> input = new ArrayList<>();
        for (int i = 0; i < 200; i++) input.add(i);

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                input,
                i -> true,
                i -> i,
                i -> "group",
                Comparator.naturalOrder()
        );

        assertEquals(1, result.size());
        List<Integer> values = result.get("group");
        assertNotNull(values);
        assertEquals(100, values.size());
        // Sorted and limited, so should start from the smallest values
        assertEquals(0, values.get(0));
        assertEquals(99, values.get(99).intValue());
    }

    @Test
    @DisplayName("processDataPipeline - uses mocked predicate/transformer/grouper and verifies calls")
    void testProcessDataPipeline_withMocks() {
        List<String> data = Arrays.asList("a", "b", "c");

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data,
                stringPredicate,
                stringToInt,
                intToGroup,
                Comparator.naturalOrder()
        );

        assertTrue(result.containsKey("grp"));
        List<Integer> grpList = result.get("grp");
        assertEquals(1, grpList.size()); // deduplicated to single 42
        assertEquals(42, grpList.get(0));

        // Verify interactions occurred exactly once per element per stage
        verify(stringPredicate, times(3)).test(anyString());
        verify(stringToInt, times(3)).apply(anyString());
        verify(intToGroup, times(3)).apply(anyInt());

        verifyNoMoreInteractions(stringPredicate, stringToInt, intToGroup);
    }

    @Test
    @DisplayName("calculateStatistics - computes mean, median, quartiles, std dev and outliers")
    void testCalculateStatistics_basic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);

        // Expected computations based on source implementation:
        // sorted = [1, 2, 2, 3, 4, 100]
        // mean = 112/6 = 18.6666666667
        // median = (2 + 3)/2 = 2.5
        // q1 index = ceil(0.25 * 6) - 1 = 1 -> 2
        // q3 index = ceil(0.75 * 6) - 1 = 4 -> 4
        // iqr = 2, fences [-1, 7] => outliers: [100]
        double expectedMean = (1 + 2 + 2 + 3 + 4 + 100) / 6.0;
        double expectedMedian = (2 + 3) / 2.0;
        double expectedQ1 = 2.0;
        double expectedQ3 = 4.0;

        // Compute std dev with population variance, as per source
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        double variance = sorted.stream()
                .mapToDouble(v -> Math.pow(v - expectedMean, 2))
                .average()
                .orElse(0.0);
        double expectedStdDev = Math.sqrt(variance);

        assertEquals(expectedMean, res.getMean(), 1e-9);
        assertEquals(expectedMedian, res.getMedian(), 1e-9);
        assertEquals(expectedQ1, res.getQ1(), 1e-9);
        assertEquals(expectedQ3, res.getQ3(), 1e-9);
        assertEquals(expectedStdDev, res.getStandardDeviation(), 1e-9);

        List<Double> outliers = res.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0));
    }

    @Test
    @DisplayName("calculateStatistics - throws on null or empty list")
    void testCalculateStatistics_invalid() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult - outliers list is unmodifiable")
    void testStatisticalResult_outliersImmutability() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 100.0);
        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);
        List<Double> outliers = res.getOutliers();

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999.0));
    }

    @Test
    @DisplayName("processInParallel - aggregates results and keeps first value on duplicate keys")
    void testProcessInParallel_aggregatesAndMerges() {
        List<String> keys = Arrays.asList("a", "b", "a");

        CompletableFuture<Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, parallelProcessorString);

        Map<String, String> result = future.join();

        assertEquals(2, result.size());
        assertEquals("a1", result.get("a")); // first occurrence kept
        assertEquals("b1", result.get("b"));
    }

    @Test
    @DisplayName("processInParallel - propagates failures with informative message")
    void testProcessInParallel_exception() {
        List<String> keys = Arrays.asList("x", "y");

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, parallelProcessorInt);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        Throwable cause = ex.getCause();
        assertNotNull(cause);
        assertTrue(cause instanceof RuntimeException);
        assertTrue(cause.getMessage().contains("Processing failed for key: x"));
        assertNotNull(cause.getCause());
        assertTrue(cause.getCause() instanceof IllegalStateException);
        assertEquals("boom", cause.getCause().getMessage());
    }

    @Test
    @DisplayName("findShortestPaths - computes shortest distances including unreachable nodes")
    void testFindShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("C", new HashMap<>());
        graph.put("D", new HashMap<>());
        graph.put("E", new HashMap<>()); // unreachable

        graph.get("A").put("B", 1);
        graph.get("A").put("C", 4);
        graph.get("B").put("C", 2);
        graph.get("B").put("D", 5);
        graph.get("C").put("D", 1);

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths - throws on invalid graph or start node")
    void testFindShortestPaths_invalid() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}