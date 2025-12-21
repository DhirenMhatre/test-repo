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
import java.util.function.Function;
import java.util.function.Predicate;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor processor;

    @Mock
    private Predicate<String> mockPredicate;

    @Mock
    private Function<String, Integer> mockTransformerInt;

    @Mock
    private Function<String, String> mockStringProcessor;

    @AfterEach
    void tearDown() {
        // Ensure the executor service is shutdown to avoid hanging threads after tests
        processor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline returns empty map for null or empty input")
    void testProcessDataPipelineReturnsEmptyMapForNullOrEmpty() {
        Map<String, List<String>> resultNull = processor.<String, String>processDataPipeline(
                null, s -> true, s -> s, s -> "group", Comparator.naturalOrder());
        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        Map<String, List<String>> resultEmpty = processor.<String, String>processDataPipeline(
                Collections.emptyList(), s -> true, s -> s, s -> "group", Comparator.naturalOrder());
        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline applies filter, transformer, sorting, grouping, dedup, and per-group limit")
    void testProcessDataPipelineAppliesFilterTransformerGroupingDedupAndLimit() {
        // Prepare 150 unique values for one group to trigger the limit(100)
        List<String> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(String.format("a%03d", i));
        }

        Map<String, List<String>> result = processor.<String, String>processDataPipeline(
                data,
                s -> true,
                s -> s, // identity transformer
                s -> s.substring(0, 1), // group by first letter
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.containsKey("a"));
        List<String> groupA = result.get("a");
        assertEquals(100, groupA.size());
        assertEquals("a000", groupA.get(0));
        assertEquals("a099", groupA.get(99));
    }

    @Test
    @DisplayName("processDataPipeline filters out nulls produced by transformer")
    void testProcessDataPipelineFiltersOutNulls() {
        List<String> data = Arrays.asList("keep1", "skip", "keep2");

        Map<String, List<String>> result = processor.<String, String>processDataPipeline(
                data,
                s -> true,
                s -> "skip".equals(s) ? null : s,
                s -> s,
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.containsKey("keep1"));
        assertTrue(result.containsKey("keep2"));
        assertFalse(result.containsKey("skip"));
    }

    @Test
    @DisplayName("processDataPipeline uses provided Predicate and Function (Mockito verification)")
    void testProcessDataPipelineWithMocks_andVerifications() {
        List<String> data = Arrays.asList("a", "b", "c");

        when(mockPredicate.test("a")).thenReturn(true);
        when(mockPredicate.test("b")).thenReturn(false);
        when(mockPredicate.test("c")).thenReturn(true);

        when(mockTransformerInt.apply("a")).thenReturn(1);
        when(mockTransformerInt.apply("c")).thenReturn(3);

        Map<String, List<Integer>> result = processor.<String, Integer>processDataPipeline(
                data,
                mockPredicate,
                mockTransformerInt,
                v -> (v % 2 == 0) ? "even" : "odd",
                Comparator.naturalOrder()
        );

        // Verify predicate evaluated for each item
        verify(mockPredicate, times(1)).test("a");
        verify(mockPredicate, times(1)).test("b");
        verify(mockPredicate, times(1)).test("c");

        // Transformer should only be applied for items that passed filter
        verify(mockTransformerInt, times(1)).apply("a");
        verify(mockTransformerInt, times(1)).apply("c");
        verify(mockTransformerInt, never()).apply("b");

        assertNotNull(result);
        assertTrue(result.containsKey("odd"));
        assertEquals(Arrays.asList(1, 3), result.get("odd"));
        assertFalse(result.containsKey("even"));
    }

    @Test
    @DisplayName("calculateStatistics computes mean, median, quartiles, stddev and outliers (IQR method)")
    void testCalculateStatisticsComputesMetricsAndOutliers() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult stats = processor.calculateStatistics(values);

        assertNotNull(stats);
        assertEquals(19.1666666667, stats.getMean(), 1e-9);
        assertEquals(3.5, stats.getMedian(), 1e-9);
        assertEquals(2.0, stats.getQ1(), 1e-9);
        assertEquals(5.0, stats.getQ3(), 1e-9);
        assertEquals(36.180110, stats.getStandardDeviation(), 1e-6);

        List<Double> outliers = stats.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);

        // Ensure outliers list is unmodifiable
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999.0));
    }

    @Test
    @DisplayName("calculateStatistics throws IllegalArgumentException for null or empty list")
    void testCalculateStatisticsThrowsOnNullOrEmpty() {
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> processor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel returns completed map with computed values")
    void testProcessInParallelReturnsResultsMapping() {
        List<String> keys = Arrays.asList("a", "b", "c");

        when(mockStringProcessor.apply("a")).thenReturn("A");
        when(mockStringProcessor.apply("b")).thenReturn("B");
        when(mockStringProcessor.apply("c")).thenReturn("C");

        Map<String, String> result = processor.processInParallel(keys, mockStringProcessor).join();

        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));

        verify(mockStringProcessor, times(1)).apply("a");
        verify(mockStringProcessor, times(1)).apply("b");
        verify(mockStringProcessor, times(1)).apply("c");
    }

    @Test
    @DisplayName("processInParallel with duplicate keys keeps the first result (merge function)")
    void testProcessInParallelWithDuplicateKeysKeepsFirstValue() {
        List<String> keys = Arrays.asList("x", "x");

        when(mockStringProcessor.apply("x")).thenReturn("first", "second");

        Map<String, String> result = processor.processInParallel(keys, mockStringProcessor).join();

        assertEquals(1, result.size());
        assertEquals("first", result.get("x"));
        verify(mockStringProcessor, times(2)).apply("x");
    }

    @Test
    @DisplayName("processInParallel completes exceptionally when a task throws")
    void testProcessInParallelCompletesExceptionallyOnFailure() {
        List<String> keys = Arrays.asList("k1", "k2");

        when(mockStringProcessor.apply("k1")).thenThrow(new RuntimeException("boom"));
        when(mockStringProcessor.apply("k2")).thenReturn("ok");

        assertThrows(CompletionException.class, () -> processor.processInParallel(keys, mockStringProcessor).join());

        verify(mockStringProcessor, times(1)).apply("k1");
        verify(mockStringProcessor, times(1)).apply("k2");
    }

    @Test
    @DisplayName("findShortestPaths computes correct distances including unreachable nodes")
    void testFindShortestPathsComputesCorrectDistancesIncludingUnreachable() {
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

        Map<String, Integer> distances = processor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths throws for invalid graph or missing start node")
    void testFindShortestPathsThrowsOnInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("B", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> processor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown is idempotent and does not throw when called multiple times")
    void testShutdownIsIdempotent() {
        processor.shutdown();
        // Call again should not throw
        processor.shutdown();
    }
}