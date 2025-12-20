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
import java.util.function.Function;
import java.util.function.Predicate;

@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    @InjectMocks
    private DataProcessor dataProcessor;

    @Mock
    private Function<String, String> processorFunction;

    @BeforeEach
    void setUp() {
        // @InjectMocks creates a fresh instance per test; nothing else required
        assertNotNull(dataProcessor);
    }

    @AfterEach
    void tearDown() {
        // Ensure executor is shutdown to avoid thread leaks
        dataProcessor.shutdown();
    }

    // processDataPipeline tests

    @Test
    @DisplayName("processDataPipeline returns empty map when data is null")
    void processDataPipeline_nullData_returnsEmpty() {
        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                null,
                s -> true,
                s -> s,
                s -> s,
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline returns empty map when data is empty")
    void processDataPipeline_emptyData_returnsEmpty() {
        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                s -> s,
                s -> s,
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline applies filter, transformer, sorter, grouping, and deduplication")
    void processDataPipeline_fullPipeline_behavesAsExpected() {
        List<String> data = Arrays.asList(
                "apple", "apricot", "banana", "avocado",
                "banana", "blueberry", "apple", ""
        );

        Predicate<String> filter = s -> s != null && !s.isEmpty();
        Function<String, String> transformer = s -> s; // identity
        Function<String, String> grouper = s -> s.substring(0, 1).toUpperCase();
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                data,
                filter,
                transformer,
                grouper,
                sorter
        );

        assertNotNull(result);
        assertEquals(2, result.size());

        List<String> groupA = result.get("A");
        List<String> groupB = result.get("B");

        assertNotNull(groupA);
        assertNotNull(groupB);

        // Sorted and deduplicated within each group
        assertEquals(Arrays.asList("apple", "apricot", "avocado"), groupA);
        assertEquals(Arrays.asList("banana", "blueberry"), groupB);
    }

    @Test
    @DisplayName("processDataPipeline drops null transformer outputs")
    void processDataPipeline_dropsNullTransformerOutputs() {
        List<String> data = Arrays.asList("apple", "banana", "avocado");

        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                data,
                s -> true,
                s -> "banana".equals(s) ? null : s,
                s -> s.substring(0, 1).toUpperCase(),
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertFalse(result.containsKey("B"));
        assertTrue(result.containsKey("A"));
        assertEquals(Arrays.asList("apple", "avocado"), result.get("A"));
    }

    @Test
    @DisplayName("processDataPipeline enforces limit per group to 100 items")
    void processDataPipeline_enforcesLimitPerGroup() {
        // Create 105 unique items all in group "A"
        List<String> data = new ArrayList<>();
        for (int i = 0; i < 105; i++) {
            data.add("a" + i);
        }

        Map<String, List<String>> result = dataProcessor.<String, String>processDataPipeline(
                data,
                s -> true,
                s -> s, // identity
                s -> s.substring(0, 1).toUpperCase(), // "A" group
                Comparator.naturalOrder()
        );

        assertTrue(result.containsKey("A"));
        assertEquals(100, result.get("A").size());
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics computes basic stats without outliers")
    void calculateStatistics_basicStats_noOutliers() {
        List<Double> values = Arrays.asList(10.0, 20.0, 30.0, 40.0);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        assertEquals(25.0, stats.getMean(), 1e-9);
        assertEquals(25.0, stats.getMedian(), 1e-9);
        assertEquals(10.0, stats.getQ1(), 1e-9);
        assertEquals(30.0, stats.getQ3(), 1e-9);
        // Population standard deviation: sqrt( ((-15)^2 + (-5)^2 + 5^2 + 15^2) / 4 ) = sqrt(500/4) = sqrt(125)
        assertEquals(Math.sqrt(125.0), stats.getStandardDeviation(), 1e-9);
        assertTrue(stats.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics detects outliers and percentile calculations")
    void calculateStatistics_detectsOutliers_andPercentiles() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        assertEquals(22.0, stats.getMean(), 1e-9);
        assertEquals(3.0, stats.getMedian(), 1e-9);
        assertEquals(2.0, stats.getQ1(), 1e-9);
        assertEquals(4.0, stats.getQ3(), 1e-9);
        // Population std dev: sqrt( (441 + 400 + 361 + 324 + 6084) / 5 ) = sqrt(7610/5)
        assertEquals(Math.sqrt(1522.0), stats.getStandardDeviation(), 1e-9);

        List<Double> outliers = stats.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics throws on null or empty list")
    void calculateStatistics_throwsOnNullOrEmpty() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult outliers list is unmodifiable")
    void statisticalResult_outliersUnmodifiable() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);
        List<Double> outliers = stats.getOutliers();

        assertNotNull(outliers);
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(100.0));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel processes keys and aggregates results successfully")
    void processInParallel_success() throws Exception {
        List<String> keys = Arrays.asList("a", "b", "c");

        when(processorFunction.apply(anyString())).thenAnswer(inv -> ((String) inv.getArgument(0)).toUpperCase());

        CompletableFuture<Map<String, String>> future = dataProcessor.<String>processInParallel(keys, processorFunction);
        Map<String, String> result = future.get(5, TimeUnit.SECONDS);

        assertEquals(3, result.size());
        assertEquals("A", result.get("a"));
        assertEquals("B", result.get("b"));
        assertEquals("C", result.get("c"));

        verify(processorFunction, times(3)).apply(anyString());
    }

    @Test
    @DisplayName("processInParallel completes exceptionally when a processor throws")
    void processInParallel_exceptionPropagation() {
        List<String> keys = Arrays.asList("good", "bad", "another");

        when(processorFunction.apply(eq("good"))).thenReturn("GOOD");
        when(processorFunction.apply(eq("another"))).thenReturn("ANOTHER");
        when(processorFunction.apply(eq("bad"))).thenThrow(new RuntimeException("boom"));

        CompletableFuture<Map<String, String>> future = dataProcessor.<String>processInParallel(keys, processorFunction);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));

        verify(processorFunction, times(3)).apply(anyString());
    }

    @Test
    @DisplayName("processInParallel handles duplicate keys by keeping the first occurrence")
    void processInParallel_duplicateKeys_keepFirst() throws Exception {
        List<String> keys = Arrays.asList("dup", "dup", "x");

        when(processorFunction.apply(eq("dup"))).thenReturn("VALUE");
        when(processorFunction.apply(eq("x"))).thenReturn("X");

        CompletableFuture<Map<String, String>> future = dataProcessor.<String>processInParallel(keys, processorFunction);
        Map<String, String> result = future.get(5, TimeUnit.SECONDS);

        // Distinct keys in the result: "dup" and "x"
        assertEquals(2, result.size());
        assertEquals("VALUE", result.get("dup"));
        assertEquals("X", result.get("x"));

        verify(processorFunction, times(3)).apply(anyString());
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths computes correct shortest paths in a weighted graph")
    void findShortestPaths_basicGraph() {
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
        graph.put("D", new HashMap<>());
        // Add an unreachable node
        graph.put("E", new HashMap<>());

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue()); // Unreachable remains MAX_VALUE
    }

    @Test
    @DisplayName("findShortestPaths throws IllegalArgumentException for invalid graph or start node")
    void findShortestPaths_invalidInput_throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    // shutdown tests

    @Test
    @DisplayName("shutdown completes without throwing")
    void shutdown_isSafeToCall() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
        // Calling shutdown again should also not throw
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}