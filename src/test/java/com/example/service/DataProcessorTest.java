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
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.Comparator;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Function<String, Integer> mockFunction;

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: groups, sorts, de-duplicates, and limits per group")
    void processDataPipeline_groupsSortsDistinctAndLimits() {
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 200; i++) data.add(i);

        Predicate<Integer> filter = i -> true;
        Function<Integer, Integer> transformer = Integer::intValue;
        Function<Integer, String> grouper = i -> "all";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertEquals(1, result.size());
        List<Integer> group = result.get("all");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(0, group.get(0));
        assertEquals(99, group.get(99));
        // Ensure distinct behavior (no duplicates within the limited list)
        Set<Integer> distinct = new HashSet<>(group);
        assertEquals(group.size(), distinct.size());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void processDataPipeline_nullOrEmpty_returnsEmptyMap() {
        Map<String, List<Integer>> resNull =
                dataProcessor.<Integer, Integer>processDataPipeline(null, i -> true, i -> i, i -> "x", Comparator.naturalOrder());
        assertTrue(resNull.isEmpty());

        Map<String, List<Integer>> resEmpty =
                dataProcessor.<Integer, Integer>processDataPipeline(Collections.emptyList(), i -> true, i -> i, i -> "x", Comparator.naturalOrder());
        assertTrue(resEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: filters input and removes nulls produced by transformer")
    void processDataPipeline_filtersAndRemovesNulls() {
        List<String> data = Arrays.asList("a", "bb", "ccc", "dddd", "eee");
        Predicate<String> filter = s -> s != null && !s.isEmpty();
        Function<String, Integer> transformer = s -> (s.length() == 3) ? null : s.length();
        Function<Integer, String> grouper = len -> "len-" + len;
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result =
                dataProcessor.<String, Integer>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertFalse(result.containsKey("len-3"));
        assertTrue(result.containsKey("len-1"));
        assertTrue(result.containsKey("len-2"));
        assertTrue(result.containsKey("len-4"));
        assertEquals(Arrays.asList(1), result.get("len-1"));
        assertEquals(Arrays.asList(2), result.get("len-2"));
        assertEquals(Arrays.asList(4), result.get("len-4"));
    }

    @Test
    @DisplayName("processDataPipeline: de-duplicates within each group independently")
    void processDataPipeline_distinctWithinEachGroup() {
        List<String> data = Arrays.asList("apple", "Apple", "apricot", "apricot", "banana", "Banana", "banana");
        Predicate<String> filter = Objects::nonNull;
        Function<String, String> transformer = s -> s.toLowerCase(Locale.ROOT);
        Function<String, String> grouper = s -> String.valueOf(s.charAt(0));
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(data, filter, transformer, grouper, sorter);

        List<String> aGroup = result.get("a");
        List<String> bGroup = result.get("b");
        assertNotNull(aGroup);
        assertNotNull(bGroup);
        assertEquals(Arrays.asList("apple", "apricot"), aGroup);
        assertEquals(Collections.singletonList("banana"), bGroup);
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev, and outliers")
    void calculateStatistics_basicMetricsAndOutliers() {
        List<Double> values = Arrays.asList(1d, 2d, 2d, 3d, 4d, 100d);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);

        assertAll(
                () -> assertEquals(112d / 6d, res.getMean(), 1e-9),
                () -> assertEquals(2.5d, res.getMedian(), 1e-9),
                () -> assertEquals(2d, res.getQ1(), 1e-9),
                () -> assertEquals(4d, res.getQ3(), 1e-9),
                () -> assertEquals(Math.sqrt(11915d / 9d), res.getStandardDeviation(), 1e-9),
                () -> {
                    List<Double> outliers = res.getOutliers();
                    assertEquals(Collections.singletonList(100d), outliers);
                    assertThrows(UnsupportedOperationException.class, () -> outliers.add(1d));
                }
        );
    }

    @Test
    @DisplayName("calculateStatistics: throws for null or empty input")
    void calculateStatistics_nullOrEmpty_throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: completes successfully and aggregates results")
    void processInParallel_success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");
        when(mockFunction.apply("a")).thenReturn(1);
        when(mockFunction.apply("bb")).thenReturn(2);
        when(mockFunction.apply("ccc")).thenReturn(3);

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockFunction);

        Map<String, Integer> result = future.join();

        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));

        verify(mockFunction, times(1)).apply("a");
        verify(mockFunction, times(1)).apply("bb");
        verify(mockFunction, times(1)).apply("ccc");
        verifyNoMoreInteractions(mockFunction);
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a task throws")
    void processInParallel_exceptionally() {
        List<String> keys = Arrays.asList("ok", "fail", "ok2");
        when(mockFunction.apply("ok")).thenReturn(1);
        when(mockFunction.apply("ok2")).thenReturn(2);
        when(mockFunction.apply("fail")).thenThrow(new IllegalStateException("boom"));

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.<Integer>processInParallel(keys, mockFunction);

        RuntimeException ex = assertThrows(RuntimeException.class, future::join);
        assertTrue(ex.getMessage().contains("Processing failed for key: fail"));
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof IllegalStateException);
        assertEquals("boom", ex.getCause().getMessage());
    }

    @Test
    @DisplayName("processInParallel: duplicate keys keep the first value")
    void processInParallel_duplicateKeys_usesFirstValue() {
        List<String> keys = Arrays.asList("x", "x", "x");
        when(mockFunction.apply("x")).thenReturn(1, 2, 3);

        Map<String, Integer> result = dataProcessor.<Integer>processInParallel(keys, mockFunction).join();

        assertEquals(1, result.size());
        assertEquals(1, result.get("x"));
        verify(mockFunction, times(3)).apply("x");
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest paths on a small graph")
    void findShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 4)));
        graph.put("B", new HashMap<>(Map.of("C", 2, "D", 5)));
        graph.put("C", new HashMap<>(Map.of("D", 1)));
        graph.put("D", new HashMap<>());
        graph.put("E", new HashMap<>()); // Unreachable

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C"));
        assertEquals(4, (int) distances.get("D"));
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for invalid graph or start node")
    void findShortestPaths_invalid_throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", Map.of("B", 1));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    @Test
    @DisplayName("shutdown: can be called multiple times without error")
    void shutdown_isIdempotent() {
        assertDoesNotThrow(() -> {
            dataProcessor.shutdown();
            dataProcessor.shutdown();
        });
    }
}