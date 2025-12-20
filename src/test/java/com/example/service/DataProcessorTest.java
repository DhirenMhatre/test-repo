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
import java.util.Comparator;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @BeforeEach
    void setUp() {
        // @InjectMocks constructs DataProcessor
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void processDataPipeline_returnsEmptyForNullOrEmpty() {
        Map<String, List<Integer>> resultNull = dataProcessor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                String::length,
                l -> "LEN_" + l,
                Comparator.naturalOrder());

        Map<String, List<Integer>> resultEmpty = dataProcessor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                String::length,
                l -> "LEN_" + l,
                Comparator.naturalOrder());

        assertTrue(resultNull.isEmpty());
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: respects filter, transform, sort, group, distinct")
    void processDataPipeline_respectsFilterMapGroupSortAndDistinct() {
        List<String> data = Arrays.asList("apple", "apricot", "banana", "avocado", "apple");
        Predicate<String> filter = s -> s != null && s.startsWith("a");
        Function<String, Integer> transformer = String::length;
        Function<Integer, String> grouper = len -> "LEN_" + len;
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data, filter, transformer, grouper, sorter);

        assertEquals(2, result.size());
        assertTrue(result.containsKey("LEN_5"));
        assertTrue(result.containsKey("LEN_7"));

        // Distinct within groups
        assertEquals(Collections.singletonList(5), result.get("LEN_5"));
        assertEquals(Collections.singletonList(7), result.get("LEN_7"));
    }

    @Test
    @DisplayName("processDataPipeline: limits to 100 items per group and preserves sorted order")
    void processDataPipeline_limitsTo100PerGroup() {
        // Create 150 unique integers as strings; transform to int; group all into single key
        List<String> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(String.valueOf(i));
        }
        Predicate<String> filter = Objects::nonNull;
        Function<String, Integer> transformer = Integer::valueOf;
        Function<Integer, String> grouper = i -> "ALL";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                data, filter, transformer, grouper, sorter);

        assertEquals(1, result.size());
        List<Integer> list = result.get("ALL");
        assertNotNull(list);
        assertEquals(100, list.size());
        // First 100 sorted integers from 0..99
        for (int i = 0; i < 100; i++) {
            assertEquals(i, list.get(i));
        }
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std-dev and detects outliers")
    void calculateStatistics_computesCorrectValuesAndOutliers() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0, 100.0);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(19.1666667, result.getMean(), 1e-6);
        assertEquals(3.5, result.getMedian(), 1e-6);
        assertEquals(2.0, result.getQ1(), 1e-6);
        assertEquals(5.0, result.getQ3(), 1e-6);
        assertEquals(36.162, result.getStandardDeviation(), 1e-3);

        List<Double> outliers = result.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-6);

        // Ensure outliers list is unmodifiable
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(10.0));
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException for null or empty input")
    void calculateStatistics_throwsForNullOrEmpty() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys concurrently and aggregates results")
    void processInParallel_aggregatesResults() {
        @SuppressWarnings("unchecked")
        Function<String, Integer> processor = mock(Function.class);

        List<String> keys = Arrays.asList("k1", "k2", "k1");

        when(processor.apply("k1")).thenReturn(1, 3);
        when(processor.apply("k2")).thenReturn(2);

        CompletableFuture<Map<String, Integer>> future = dataProcessor.<Integer>processInParallel(keys, processor);
        Map<String, Integer> result = future.join();

        // For duplicate key "k1", the first value (1) should be kept
        assertEquals(2, result.size());
        assertEquals(1, result.get("k1"));
        assertEquals(2, result.get("k2"));

        // Verify interactions
        verify(processor, times(2)).apply("k1");
        verify(processor, times(1)).apply("k2");
        verifyNoMoreInteractions(processor);
    }

    @Test
    @DisplayName("processInParallel: propagates exceptions from processor as CompletionException")
    void processInParallel_propagatesProcessorException() {
        @SuppressWarnings("unchecked")
        Function<String, Integer> processor = mock(Function.class);

        List<String> keys = Arrays.asList("ok", "bad", "later");

        when(processor.apply("ok")).thenReturn(42);
        when(processor.apply("bad")).thenThrow(new IllegalStateException("boom"));
        when(processor.apply("later")).thenReturn(7);

        CompletableFuture<Map<String, Integer>> future = dataProcessor.<Integer>processInParallel(keys, processor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("findShortestPaths: computes correct shortest distances in weighted graph")
    void findShortestPaths_computesCorrectDistances() {
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
        assertEquals(3, distances.get("C"));
        assertEquals(4, distances.get("D"));
    }

    @Test
    @DisplayName("findShortestPaths: leaves unreachable nodes at Integer.MAX_VALUE")
    void findShortestPaths_unreachableNodesHaveMaxValue() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>());
        graph.put("B", new HashMap<>());
        graph.put("E", new HashMap<>()); // Unreachable from A

        graph.get("A").put("B", 2);

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(2, distances.get("B"));
        assertEquals(Integer.MAX_VALUE, distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths: throws IllegalArgumentException for invalid graph or start node")
    void findShortestPaths_throwsForInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: can be called safely without exceptions")
    void shutdown_doesNotThrow() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}