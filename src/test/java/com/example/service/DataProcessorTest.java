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

import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Comparator;
import java.util.function.Function;
import java.util.function.Predicate;

class DataProcessorTest {

    private DataProcessor dataProcessor;






    @BeforeEach
    void setUp() {
        dataProcessor = new DataProcessor();
    }

    @AfterEach
    void tearDown() {
        if (dataProcessor != null) {
            dataProcessor.shutdown();
        }
    }

    @Test
    @DisplayName("processDataPipeline: filters, transforms, sorts, groups, de-duplicates correctly")
    void processDataPipeline_basicWorkflow() {
        List<Integer> data = Arrays.asList(5, 2, 2, 8, 3, 10, 4, 12);

        // Filter: include all except 3 (to avoid odd group)
            Integer v = inv.getArgument(0);
            return v != 3;
        });

        // Transformer:
        // - 2 -> null (should be filtered out after transform)
        // - 5 -> 10
        // - 8 -> 8
        // - 10 -> 20
        // - 4 -> 8
        // - 12 -> 24
        // Others -> identity
            Integer x = inv.getArgument(0);
            if (x == 2) return null;
            if (x == 5) return 10;
            if (x == 8) return 8;
            if (x == 10) return 20;
            if (x == 4) return 8;
            if (x == 12) return 24;
            return x;
        });

        // Grouper: even/odd by transformed value
            Integer v = inv.getArgument(0);
            return (v != null && v % 2 == 0) ? "even" : "odd";
        });

        // Comparator: natural order
                .thenAnswer(inv -> {
                    Integer a = inv.getArgument(0);
                    Integer b = inv.getArgument(1);
                    return Integer.compare(a, b);
                });

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filterMock, transformerMock, grouperMock, comparatorMock);

        assertNotNull(result);
        assertTrue(result.containsKey("even"));
        assertFalse(result.containsKey("odd")); // All transformed values are even (except null filtered out)

        List<Integer> evens = result.get("even");
        assertEquals(Arrays.asList(8, 10, 20, 24), evens);

        // Verify expected interactions occurred and no unexpected extras
        verifyNoMoreInteractions(grouperMock, comparatorMock);
    }

    @Test
    @DisplayName("processDataPipeline: returns empty map when input is null or empty")
    void processDataPipeline_nullOrEmpty() {
        Map<String, List<Integer>> nullResult = dataProcessor.processDataPipeline(
                null, x -> true, x -> x, Object::toString, Comparator.naturalOrder());
        assertTrue(nullResult.isEmpty());

        Map<String, List<Integer>> emptyResult = dataProcessor.processDataPipeline(
                Collections.emptyList(), x -> true, x -> x, Object::toString, Comparator.naturalOrder());
        assertTrue(emptyResult.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: enforces per-group limit of 100 after de-duplication and sorting")
    void processDataPipeline_groupLimitAndDedup() {
        List<Integer> data = new ArrayList<>();
        for (int i = 1; i <= 150; i++) {
            data.add(i);
        }

                .thenAnswer(inv -> {
                    Integer a = inv.getArgument(0);
                    Integer b = inv.getArgument(1);
                    return Integer.compare(a, b);
                });

        Map<String, List<Integer>> result = dataProcessor.processDataPipeline(
                data, filterMock, transformerMock, grouperMock, comparatorMock);

        assertNotNull(result);
        assertTrue(result.containsKey("A"));
        List<Integer> group = result.get("A");
        assertEquals(100, group.size());
        // Should contain the first 100 integers (sorted ascending, then limited)
        for (int i = 1; i <= 100; i++) {
            assertEquals(i, group.get(i - 1));
        }

    }

    @Test
    @DisplayName("calculateStatistics: computes mean, median, quartiles, stdDev and outliers correctly")
    void calculateStatistics_validData() {
        List<Double> values = Arrays.asList(1d, 2d, 3d, 4d, 5d, 6d, 7d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(16.0, result.getMean(), 1e-9);
        assertEquals(4.5, result.getMedian(), 1e-9);
        // Using percentile method implemented: q1=2, q3=6 for this dataset
        assertEquals(2.0, result.getQ1(), 1e-9);
        assertEquals(6.0, result.getQ3(), 1e-9);
        double expectedStdDev = Math.sqrt(1011.5);
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-9);
        assertEquals(1, result.getOutliers().size());
        assertEquals(100.0, result.getOutliers().get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: throws on null or empty input")
    void calculateStatistics_invalidInput() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("processInParallel: successfully processes keys asynchronously and aggregates results")
    void processInParallel_success() {
        List<String> keys = Arrays.asList("a", "bb", "ccc");

            String s = inv.getArgument(0);
            return s.length();
        });

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.processInParallel(keys, asyncProcessorMock);

        Map<String, Integer> result = future.join();

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));

        verifyNoMoreInteractions(asyncProcessorMock);
    }

    @Test
    @DisplayName("processInParallel: completes exceptionally when a processor throws")
    void processInParallel_failure() {
        List<String> keys = Arrays.asList("ok1", "boom", "ok2");

            String s = inv.getArgument(0);
            return s.length();
        });

        CompletableFuture<Map<String, Integer>> future =
                dataProcessor.processInParallel(keys, asyncProcessorMock);

        assertThrows(CompletionException.class, future::join);
    }

    @Test
    @DisplayName("findShortestPaths: returns correct shortest distances from start node")
    void findShortestPaths_validGraph() {
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
        graph.put("E", Collections.emptyMap()); // Unreachable

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C"));
        assertEquals(4, (int) distances.get("D"));
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths: throws for null graph or invalid start node")
    void findShortestPaths_invalidInput() {
        assertThrows(IllegalArgumentException.class,
                () -> dataProcessor.findShortestPaths(null, "A"));

        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", Collections.singletonMap("Y", 1));
        assertThrows(IllegalArgumentException.class,
                () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("StatisticalResult: getters work and outliers list is unmodifiable/defensive")
    void statisticalResult_gettersAndImmutability() {
        List<Double> outliers = new ArrayList<>(Arrays.asList(10.0, 20.0));
        DataProcessor.StatisticalResult r =
                new DataProcessor.StatisticalResult(1.0, 2.0, 0.5, 3.0, 0.7, outliers);

        assertEquals(1.0, r.getMean(), 1e-9);
        assertEquals(2.0, r.getMedian(), 1e-9);
        assertEquals(0.5, r.getQ1(), 1e-9);
        assertEquals(3.0, r.getQ3(), 1e-9);
        assertEquals(0.7, r.getStandardDeviation(), 1e-9);
        assertEquals(Arrays.asList(10.0, 20.0), r.getOutliers());

        // Attempt to modify the returned list should fail
        assertThrows(UnsupportedOperationException.class, () -> r.getOutliers().add(30.0));

        // Modifying the original list should not affect the StatisticalResult
        outliers.add(30.0);
        assertEquals(Arrays.asList(10.0, 20.0), r.getOutliers());
    }

    @Test
    @DisplayName("shutdown: shuts down internal executor service")
    void shutdown_shutsDownExecutor() throws Exception {
        dataProcessor.shutdown();

        Field f = DataProcessor.class.getDeclaredField("executorService");
        f.setAccessible(true);
        Object exec = f.get(dataProcessor);
        assertTrue(exec instanceof java.util.concurrent.ExecutorService);
        assertTrue(((java.util.concurrent.ExecutorService) exec).isShutdown());
    }
}