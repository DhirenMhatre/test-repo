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

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;

import java.util.stream.Stream;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.function.Function;
import java.util.function.Predicate;

class DataProcessorTest {

    private DataProcessor dataProcessor;

    private Predicate<Integer> predicateMock;

    private Function<Integer, String> transformerMock;

    private Function<String, String> grouperMock;

    private Function<String, Integer> mockProcessor;

    @BeforeEach
    void setUp() {
    }

    @AfterEach
    void tearDown() {
        // Ensure executor is stopped to avoid thread leaks
        dataProcessor.shutdown();
    }

    @Test
    @DisplayName("processDataPipeline: filters, maps, removes nulls, sorts and groups using mocks")
    void testProcessDataPipeline_WithMocks() {
        List<Integer> data = Arrays.asList(1, 2, 3, 4);

            Integer v = inv.getArgument(0);
            return v > 1; // filter out 1
        });

            Integer v = inv.getArgument(0);
            // Return null for 3 to test null filtering
            return v == 3 ? null : "v" + (v * 10);
        });


        Map<String, List<String>> result =
                dataProcessor.<Integer, String>processDataPipeline(
                        data,
                        predicateMock,
                        transformerMock,
                        grouperMock,
                        Comparator.naturalOrder()
                );

        assertEquals(1, result.size());
        assertTrue(result.containsKey("G1"));
        List<String> group = result.get("G1");
        assertEquals(Arrays.asList("v20", "v40"), group);

    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when data is null")
    void testProcessDataPipeline_NullData() {
        Map<String, List<String>> result =
                dataProcessor.<Integer, String>processDataPipeline(
                        null,
                        i -> true,
                        Object::toString,
                        s -> "G",
                        Comparator.naturalOrder()
                );
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: applies distinct and limit per group")
    void testProcessDataPipeline_DistinctAndLimit() {
        List<Integer> data = IntStream.range(0, 150).boxed().collect(Collectors.toList());

        Map<String, List<String>> result =
                dataProcessor.<Integer, String>processDataPipeline(
                        data,
                        i -> true,
                        i -> "S" + i,
                        s -> "G",
                        Comparator.naturalOrder()
                );

        assertEquals(1, result.size());
        List<String> group = result.get("G");
        assertNotNull(group);
        assertEquals(100, group.size());

        List<String> expected = data.stream()
                .map(i -> "S" + i)
                .sorted(Comparator.naturalOrder())
                .distinct()
                .limit(100)
                .collect(Collectors.toList());

        assertEquals(expected, group);
    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, std dev and outliers")
    void testCalculateStatistics_Computation() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 100d);

        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);

        assertEquals(22.0, stats.getMean(), 1e-9);
        assertEquals(3.0, stats.getMedian(), 1e-9);
        assertEquals(2.0, stats.getQ1(), 1e-9);
        assertEquals(4.0, stats.getQ3(), 1e-9);

        // variance = 1522.0; stdDev = sqrt(1522.0)
        assertEquals(Math.sqrt(1522.0), stats.getStandardDeviation(), 1e-9);

        assertEquals(Collections.singletonList(100d), stats.getOutliers());
    }

    @Test
    @DisplayName("calculateStatistics: throws on null or empty input")
    void testCalculateStatistics_ThrowsOnInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult: outliers list is unmodifiable")
    void testStatisticalResult_OutliersUnmodifiable() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 100d);
        DataProcessor.StatisticalResult stats = dataProcessor.calculateStatistics(values);
        List<Double> outliers = stats.getOutliers();

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(200d));
    }

    @Test
    @DisplayName("processInParallel: completes successfully and keeps first value on duplicate keys")
    void testProcessInParallel_SuccessWithDuplicates() {
        List<String> keys = Arrays.asList("a", "b", "a");


        Map<String, Integer> result = dataProcessor.<Integer>processInParallel(keys, mockProcessor).join();

        assertEquals(2, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("b"));

    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a processor invocation fails")
    void testProcessInParallel_Failure() {
        List<String> keys = Arrays.asList("ok", "fail");


        CompletableFuture<Map<String, Integer>> future = dataProcessor.<Integer>processInParallel(keys, mockProcessor);

        assertThrows(CompletionException.class, future::join);

    }

    @Test
    @DisplayName("findShortestPaths: computes correct distances including unreachable nodes")
    void testFindShortestPaths_Computation() {
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
        graph.put("E", new HashMap<>()); // unreachable

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue());
        assertEquals(4, distances.get("D").intValue());
        assertEquals(Integer.MAX_VALUE, distances.get("E").intValue());
    }

    @Test
    @DisplayName("findShortestPaths: throws on invalid graph or start node")
    void testFindShortestPaths_InvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(Collections.emptyMap(), "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", Collections.emptyMap());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    @Test
    @DisplayName("shutdown: completes without exception")
    void testShutdown() {
        assertDoesNotThrow(() -> dataProcessor.shutdown());
    }
}
