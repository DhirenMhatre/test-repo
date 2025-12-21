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

import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutorService;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    private DataProcessor dataProcessor;

    // Declared to satisfy "mock dependencies"; DataProcessor uses an ExecutorService internally.
    private ExecutorService executorService;

    @Mock
    private Function<String, String> mockProcessor;

    @BeforeEach
    void setUp() {
        // Ensure a fresh instance for each test
        dataProcessor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_EmptyOrNullInput() {
        Map<String, List<String>> resultNull = dataProcessor.<Integer, String>processDataPipeline(
                null,
                i -> true,
                Object::toString,
                s -> "group",
                Comparator.naturalOrder()
        );
        assertNotNull(resultNull);
        assertTrue(resultNull.isEmpty());

        Map<String, List<String>> resultEmpty = dataProcessor.<Integer, String>processDataPipeline(
                Collections.emptyList(),
                i -> true,
                Object::toString,
                s -> "group",
                Comparator.naturalOrder()
        );
        assertNotNull(resultEmpty);
        assertTrue(resultEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: applies filter, transformer, sorter, grouping, distinct and limit")
    void testProcessDataPipeline_DistinctAndLimitPerGroup() {
        // Create 200 integers; transform to 120 unique strings using modulo, so dedup occurs.
        List<Integer> data = IntStream.range(0, 200).boxed().collect(Collectors.toList());

        Predicate<Integer> filter = i -> i >= 0; // keep all
        Function<Integer, String> transformer = i -> String.format("v-%03d", i % 120);
        Function<String, String> grouper = s -> "G";
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.<Integer, String>processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        assertTrue(result.containsKey("G"));
        List<String> groupList = result.get("G");

        // Expect: sorted, distinct, limited to 100
        assertNotNull(groupList);
        assertEquals(100, groupList.size(), "Should limit to 100 items per group");

        // Ensure no duplicates
        Set<String> set = new HashSet<>(groupList);
        assertEquals(groupList.size(), set.size(), "List should be distinct");

        // With natural order on "v-%03d", first 100 values should be v-000 to v-099
        assertTrue(groupList.contains("v-000"));
        assertTrue(groupList.contains("v-099"));
        assertFalse(groupList.contains("v-100"));
        assertFalse(groupList.contains("v-119"));
    }

    @Test
    @DisplayName("processDataPipeline: filters out nulls produced by transformer")
    void testProcessDataPipeline_FiltersNullTransformedValues() {
        List<Integer> data = Arrays.asList(1, 2, 3, 4);
        Predicate<Integer> filter = i -> true;
        Function<Integer, String> transformer = i -> (i % 2 == 0) ? null : "odd-" + i; // null for even numbers
        Function<String, String> grouper = s -> "GROUP";
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.<Integer, String>processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        List<String> list = result.get("GROUP");
        assertNotNull(list);
        assertEquals(2, list.size());
        assertTrue(list.contains("odd-1"));
        assertTrue(list.contains("odd-3"));
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev, and outliers")
    void testCalculateStatistics_Basic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(112.0 / 6.0, result.getMean(), 1e-9);
        assertEquals(2.5, result.getMedian(), 1e-9);
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(4.0, result.getQ3(), 1e-9);

        // Population variance/stddev as implemented
        double expectedVariance = 1323.888888888889;
        double expectedStd = Math.sqrt(expectedVariance);
        assertEquals(expectedStd, result.getStandardDeviation(), 1e-9);

        List<Double> outliers = result.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: throws for null or empty input")
    void testCalculateStatistics_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys successfully and aggregates results")
    void testProcessInParallel_Success() {
        List<String> keys = Arrays.asList("a", "b", "c");

        when(mockProcessor.apply("a")).thenReturn("A");
        when(mockProcessor.apply("b")).thenReturn("B");
        when(mockProcessor.apply("c")).thenReturn("C");

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, mockProcessor);
        Map<String, String> result = future.join();

        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));

        verify(mockProcessor, times(1)).apply("a");
        verify(mockProcessor, times(1)).apply("b");
        verify(mockProcessor, times(1)).apply("c");
        verifyNoMoreInteractions(mockProcessor);
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a key processing throws")
    void testProcessInParallel_Exception() {
        List<String> keys = Arrays.asList("ok", "bad", "ok2");

        when(mockProcessor.apply("ok")).thenReturn("OK");
        when(mockProcessor.apply("ok2")).thenReturn("OK2");
        when(mockProcessor.apply("bad")).thenThrow(new RuntimeException("boom"));

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, mockProcessor);

        assertThrows(CompletionException.class, future::join);
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph or missing start node")
    void testFindShortestPaths_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances correctly including unreachable nodes")
    void testFindShortestPaths_BasicGraph() {
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
        graph.put("E", Collections.emptyMap()); // unreachable from A

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C"));
        assertEquals(4, (int) distances.get("D"));
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E"));
    }

    @Test
    @DisplayName("shutdown: executor service is shut down")
    void testShutdown_ShutsDownExecutor() throws Exception {
        // Access private executorService via reflection
        Field field = DataProcessor.class.getDeclaredField("executorService");
        field.setAccessible(true);
        Object execBefore = field.get(dataProcessor);
        assertTrue(execBefore instanceof ExecutorService);
        ExecutorService esBefore = (ExecutorService) execBefore;
        assertFalse(esBefore.isShutdown());

        dataProcessor.shutdown();

        ExecutorService esAfter = (ExecutorService) field.get(dataProcessor);
        assertTrue(esAfter.isShutdown());
    }
}