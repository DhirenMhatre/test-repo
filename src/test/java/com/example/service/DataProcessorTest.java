package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.Disabled;
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
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.function.Predicate;

@Disabled("COMPILATION ERROR: package org.mockito.junit.jupiter does not exist. Manual review required.")
@ExtendWith(MockitoExtension.class)
class DataProcessorTest {

    private DataProcessor dataProcessor;

    @Mock
    private Function<String, String> stringProcessorMock;

    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();

        // Common stubbing
        when(stringProcessorMock.apply(eq("k1"))).thenReturn("v1");
        when(stringProcessorMock.apply(eq("k2"))).thenReturn("v2");
        when(stringProcessorMock.apply(eq("ok"))).thenReturn("ok-value");
        when(stringProcessorMock.apply(eq("bad"))).thenThrow(new RuntimeException("Processing failed for key: bad"));
    }

    @AfterEach
    void tearDown() {
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, dedups correctly")
    void testProcessDataPipeline_basicFlow() {
        List<String> data = Arrays.asList(
                "apple", "apricot", "banana", "banana", "blueberry", "avocado", "blackberry"
        );

        Predicate<String> filter = s -> s.startsWith("a") || s.startsWith("b");
        Function<String, String> transformer = String::toUpperCase;
        Function<String, String> grouper = s -> s.substring(0, 1);
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertEquals(2, result.size(), "Should have 2 groups: A and B");

        assertTrue(result.containsKey("A"));
        assertTrue(result.containsKey("B"));

        List<String> expectedA = Arrays.asList("APPLE", "APRICOT", "AVOCADO");
        List<String> expectedB = Arrays.asList("BANANA", "BLACKBERRY", "BLUEBERRY");

        assertEquals(expectedA, result.get("A"), "Group A should be sorted and deduplicated");
        assertEquals(expectedB, result.get("B"), "Group B should be sorted and deduplicated");
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when data is null")
    void testProcessDataPipeline_nullData() {
        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(null, s -> true, s -> s, s -> "G", Comparator.naturalOrder());
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when data is empty")
    void testProcessDataPipeline_emptyData() {
        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(Collections.emptyList(), s -> true, s -> s, s -> "G", Comparator.naturalOrder());
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 after deduplication")
    void testProcessDataPipeline_groupLimit() {
        List<String> data = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            data.add("a" + i);
        }

        Predicate<String> filter = s -> true;
        Function<String, String> transformer = String::toUpperCase;
        Function<String, String> grouper = s -> s.substring(0, 1);
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertEquals(1, result.size());
        assertTrue(result.containsKey("A"));
        assertEquals(100, result.get("A").size(), "Should limit to 100 per group");
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stdDev (population), and outliers (IQR)")
    void testCalculateStatistics_basic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0, 100.0);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);

        // Mean
        assertEquals(19.1666666667, res.getMean(), 1e-6);
        // Median (even count): (3 + 4)/2 = 3.5
        assertEquals(3.5, res.getMedian(), 1e-6);
        // Percentiles using ceil index rule:
        // Q1 = 25th percentile => index ceil(0.25*6)-1 = 1 => value 2.0
        // Q3 = 75th percentile => index ceil(0.75*6)-1 = 4 => value 5.0
        assertEquals(2.0, res.getQ1(), 1e-6);
        assertEquals(5.0, res.getQ3(), 1e-6);

        // Population variance/stddev
        // variance = avg(x^2) - mean^2
        double avgXSq = (1 + 4 + 9 + 16 + 25 + 10000) / 6.0;
        double mean = 115.0 / 6.0;
        double variance = avgXSq - (mean * mean);
        double expectedStdDev = Math.sqrt(variance);
        assertEquals(expectedStdDev, res.getStandardDeviation(), 1e-6);

        // Outliers via IQR (1.5 rule): only 100.0
        assertEquals(1, res.getOutliers().size());
        assertEquals(100.0, res.getOutliers().get(0), 1e-6);

        // Outliers list is unmodifiable
        assertThrows(UnsupportedOperationException.class, () -> res.getOutliers().add(999.0));
    }

    @Test
    @DisplayName("calculateStatistics: throws IllegalArgumentException on null or empty input")
    void testCalculateStatistics_invalidInputs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: processes keys concurrently, aggregates into map, dedupes duplicate keys keeping first occurrence")
    void testProcessInParallel_successAndDuplicateKeys() {
        List<String> keys = Arrays.asList("k1", "k2", "k1");

        CompletableFuture<Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, stringProcessorMock);

        Map<String, String> result = future.join();

        assertEquals(2, result.size());
        assertEquals("v1", result.get("k1"));
        assertEquals("v2", result.get("k2"));
    }

    @Test
    @DisplayName("processInParallel: propagates processor exceptions as CompletionException wrapping RuntimeException with key")
    void testProcessInParallel_exceptionPropagation() {
        List<String> keys = Arrays.asList("ok", "bad");

        CompletableFuture<Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, stringProcessorMock);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
    }

    @Test
    @DisplayName("processInParallel: after shutdown, new tasks complete exceptionally")
    void testProcessInParallel_afterShutdown() {
        dataProcessor.shutdown();

        List<String> keys = Collections.singletonList("x");

        CompletableFuture<Map<String, String>> future =
                dataProcessor.<String>processInParallel(keys, stringProcessorMock);

        assertThrows(CompletionException.class, future::join);
        verifyNoMoreInteractions(stringProcessorMock);
    }

    @Test
    @DisplayName("findShortestPaths: computes shortest distances including unreachable nodes")
    void testFindShortestPaths_basic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 10)));
        graph.put("B", new HashMap<>(Map.of("C", 2)));
        graph.put("C", new HashMap<>());
        graph.put("D", new HashMap<>(Map.of("C", 1))); // disconnected from A

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C"));
        assertEquals(Integer.MAX_VALUE, distances.get("D"));
    }

    @Test
    @DisplayName("findShortestPaths: throws on invalid graph or start node")
    void testFindShortestPaths_invalidInputs() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}