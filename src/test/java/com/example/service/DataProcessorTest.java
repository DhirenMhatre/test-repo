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

    @Mock
    private Function<String, Integer> mockStringProcessor;

    @AfterEach
    void tearDown() {
        // Ensure executor is shutdown to avoid leftover threads across tests
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, de-duplicates, and limits correctly")
    void testProcessDataPipeline_BasicFlow() {
        // Arrange
        List<Integer> data = Arrays.asList(5, 1, 2, 2, 3, 3, 4);
        Predicate<Integer> filter = i -> i > 0; // keep all positive
        Function<Integer, Integer> transformer = i -> i; // identity
        Function<Integer, String> grouper = i -> (i % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        // Act
        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        // Assert
        assertNotNull(result);
        assertEquals(2, result.size());

        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));

        assertEquals(Arrays.asList(1, 3, 5), result.get("odd"));
        assertEquals(Arrays.asList(2, 4), result.get("even"));
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map for null or empty input")
    void testProcessDataPipeline_NullOrEmpty() {
        Map<String, List<Integer>> resNull = dataProcessor.processDataPipeline(
                null, i -> true, i -> i, Object::toString, Comparator.naturalOrder()
        );
        Map<String, List<Integer>> resEmpty = dataProcessor.processDataPipeline(
                Collections.emptyList(), i -> true, i -> i, Object::toString, Comparator.naturalOrder()
        );

        assertNotNull(resNull);
        assertTrue(resNull.isEmpty());

        assertNotNull(resEmpty);
        assertTrue(resEmpty.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 elements after dedup and sort")
    void testProcessDataPipeline_PerGroupLimit() {
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add(i);
        }
        Predicate<Integer> filter = i -> true;
        Function<Integer, Integer> transformer = i -> i;
        Function<Integer, String> grouper = i -> "group";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filter, transformer, grouper, sorter
        );

        assertEquals(1, result.size());
        assertTrue(result.containsKey("group"));
        List<Integer> groupList = result.get("group");
        assertEquals(100, groupList.size());
        // Expect first 100 sorted integers 0..99
        for (int i = 0; i < 100; i++) {
            assertEquals(i, groupList.get(i));
        }
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev, and outliers (no outliers case)")
    void testCalculateStatistics_Basic() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 6d, 7d, 8d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(4.5, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        // Based on calculatePercentile implementation: q1=2, q3=6 for size 8
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);
        // Population std dev for 1..8 is sqrt(5.25) ≈ 2.291287847
        assertEquals(2.291287847, result.getStandardDeviation(), 1e-9);
        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: detects outliers using IQR fences")
    void testCalculateStatistics_Outliers() {
        List<Double> values = Arrays.asList(10d, 12d, 12d, 13d, 12d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        // With current percentile method: q1=12, q3=13, IQR=1 -> fences [10.5, 14.5]
        List<Double> outliers = result.getOutliers();
        assertEquals(2, outliers.size());
        assertEquals(10.0, outliers.get(0), 1e-9);
        assertEquals(100.0, outliers.get(1), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: throws for null or empty input")
    void testCalculateStatistics_InvalidArgs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys concurrently and aggregates results (with duplicate keys preserving first)")
    void testProcessInParallel_SuccessWithDuplicates_AndMockitoVerify() {
        List<String> keys = Arrays.asList("a", "b", "a");

        when(mockStringProcessor.apply("a")).thenReturn(1);
        when(mockStringProcessor.apply("b")).thenReturn(2);

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, mockStringProcessor);
        Map<String, Integer> result = future.join();

        assertNotNull(result);
        assertEquals(2, result.size());
        assertEquals(1, result.get("a")); // first 'a' result preserved
        assertEquals(2, result.get("b"));

        verify(mockStringProcessor, times(2)).apply("a");
        verify(mockStringProcessor, times(1)).apply("b");
        verifyNoMoreInteractions(mockStringProcessor);
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when any task fails and wraps exception with key info")
    void testProcessInParallel_ExceptionPath() {
        List<String> keys = Arrays.asList("ok", "bad");

        when(mockStringProcessor.apply("ok")).thenReturn(42);
        when(mockStringProcessor.apply("bad")).thenThrow(new RuntimeException("original failure"));

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, mockStringProcessor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
        assertNotNull(ex.getCause().getCause());
        assertEquals("original failure", ex.getCause().getCause().getMessage());

        verify(mockStringProcessor, times(1)).apply("ok");
        verify(mockStringProcessor, times(1)).apply("bad");
    }

    @Test
    @DisplayName("processInParallel: returns empty map for empty key list")
    void testProcessInParallel_EmptyKeys() {
        List<String> keys = Collections.emptyList();

        // Even though processor won't be called, set a default to be safe
        when(mockStringProcessor.apply(anyString())).thenReturn(0);

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, mockStringProcessor);
        Map<String, Integer> result = future.join();

        assertNotNull(result);
        assertTrue(result.isEmpty());

        verifyNoInteractions(mockStringProcessor);
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances including unreachable nodes")
    void testFindShortestPaths_ValidGraph() {
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
        graph.put("D", new HashMap<>()); // terminal
        graph.put("E", new HashMap<>()); // unreachable

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(5, distances.size());
        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C")); // A->B->C (1+2)
        assertEquals(4, (int) distances.get("D")); // A->B->C->D (1+2+1)
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph or invalid start node")
    void testFindShortestPaths_InvalidArgs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown: can be called multiple times without exceptions")
    void testShutdown_Idempotent() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}