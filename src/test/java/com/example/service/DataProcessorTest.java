package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Function;
import java.util.function.Predicate;

class DataProcessorTest {

    private ExecutorService executorService;

    private DataProcessor dataProcessor;

    @BeforeEach
    void setUp() throws Exception {
        dataProcessor = new DataProcessor();

        // Replace the internally created executor with our own and shut down the original to avoid thread leaks
        Field f = DataProcessor.class.getDeclaredField("executorService");
        f.setAccessible(true);
        ExecutorService original = (ExecutorService) f.get(dataProcessor);
        if (original != null) {
            original.shutdownNow();
        }

        // Use a single-threaded executor to keep async operations deterministic in tests
        executorService = Executors.newSingleThreadExecutor();
        f.set(dataProcessor, executorService);
    }

    @AfterEach
    void tearDown() {
        if (executorService != null && !executorService.isShutdown()) {
            executorService.shutdownNow();
        }
    }

    @Test
    @DisplayName("processDataPipeline returns empty map for null or empty input")
    void testProcessDataPipelineEmptyOrNull() {
        Map<String, List<String>> nullResult =
                dataProcessor.<String, String>processDataPipeline(null,
                        s -> true, Function.identity(), s -> "G", Comparator.naturalOrder());
        assertTrue(nullResult.isEmpty());

        Map<String, List<String>> emptyResult =
                dataProcessor.<String, String>processDataPipeline(Collections.emptyList(),
                        s -> true, Function.identity(), s -> "G", Comparator.naturalOrder());
        assertTrue(emptyResult.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline applies filter, transform, sort, group, distinct and limit per group")
    void testProcessDataPipelineBasicFlow() {
        List<String> data = Arrays.asList(
                "apple", "banana", "apricot", "banana", "avocado", "blueberry", "almond", "apple"
        );

        Predicate<String> filter = s -> s != null && (s.startsWith("a") || s.startsWith("b"));
        Function<String, String> transformer = String::toUpperCase;
        Function<String, String> grouper = s -> s.substring(0, 1); // "A" or "B"
        Comparator<String> sorter = Comparator.naturalOrder();

        Map<String, List<String>> result =
                dataProcessor.<String, String>processDataPipeline(data, filter, transformer, grouper, sorter);

        assertEquals(2, result.size());
        assertTrue(result.containsKey("A"));
        assertTrue(result.containsKey("B"));

        List<String> groupA = result.get("A");
        List<String> groupB = result.get("B");

        assertEquals(Arrays.asList("ALMOND", "APPLE", "APRICOT", "AVOCADO"), groupA);
        assertEquals(Arrays.asList("BANANA", "BLUEBERRY"), groupB);
    }

    @Test
    @DisplayName("processDataPipeline enforces per-group limit of 100 after distinct")
    void testProcessDataPipelineLimitPerGroup() {
        List<Integer> data = new ArrayList<>();
        for (int i = 1; i <= 150; i++) {
            data.add(i);
        }

        Map<String, List<Integer>> result =
                dataProcessor.<Integer, Integer>processDataPipeline(
                        data,
                        i -> true,
                        Function.identity(),
                        i -> "GROUP",
                        Comparator.naturalOrder()
                );

        assertEquals(1, result.size());
        List<Integer> group = result.get("GROUP");
        assertNotNull(group);
        assertEquals(100, group.size());
        assertEquals(1, group.get(0));
        assertEquals(100, group.get(99));
    }

    @Test
    @DisplayName("calculateStatistics computes mean, median, quartiles, std dev, and detects outliers")
    void testCalculateStatisticsBasic() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);

        assertEquals(22.0, res.getMean(), 1e-9);
        assertEquals(3.0, res.getMedian(), 1e-9);
        assertEquals(2.0, res.getQ1(), 1e-9);
        assertEquals(4.0, res.getQ3(), 1e-9);
        assertEquals(Math.sqrt(1522.0), res.getStandardDeviation(), 1e-9);

        List<Double> outliers = res.getOutliers();
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0));
    }

    @Test
    @DisplayName("calculateStatistics throws on null or empty input")
    void testCalculateStatisticsThrows() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("StatisticalResult outliers list is unmodifiable")
    void testStatisticalResultOutliersUnmodifiable() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);
        DataProcessor.StatisticalResult res = dataProcessor.calculateStatistics(values);
        List<Double> outliers = res.getOutliers();

        assertThrows(UnsupportedOperationException.class, () -> outliers.add(999.0));
        // Ensure original remains consistent
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0));
    }

    @Test
    @DisplayName("processInParallel processes all keys and aggregates results")
    void testProcessInParallelSuccess() {
        List<String> keys = Arrays.asList("k1", "k2", "k3");
        Function<String, String> processor = k -> k.toUpperCase();

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, processor);
        Map<String, String> result = future.join();

        assertEquals(3, result.size());
        assertEquals("K1", result.get("k1"));
        assertEquals("K2", result.get("k2"));
        assertEquals("K3", result.get("k3"));
    }

    @Test
    @DisplayName("processInParallel propagates exceptions from processor and fails the future")
    void testProcessInParallelException() {
        List<String> keys = Arrays.asList("ok", "boom", "alsoOk");
        Function<String, String> processor = k -> {
            if ("boom".equals(k)) {
                throw new IllegalStateException("boom!");
            }
            return k + "-done";
        };

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, processor);

        CompletionException ex = assertThrows(CompletionException.class, future::join);
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: boom"));
    }

    @Test
    @DisplayName("findShortestPaths computes minimal distances in a directed weighted graph")
    void testFindShortestPathsBasic() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", new HashMap<>(Map.of("B", 1, "C", 4)));
        graph.put("B", new HashMap<>(Map.of("C", 2, "D", 5)));
        graph.put("C", new HashMap<>(Map.of("D", 1)));
        graph.put("D", new HashMap<>()); // terminal
        graph.put("E", new HashMap<>()); // isolated node reachable only if start is E (not in this test)

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertEquals(0, (int) distances.get("A"));
        assertEquals(1, (int) distances.get("B"));
        assertEquals(3, (int) distances.get("C"));
        assertEquals(4, (int) distances.get("D"));
        // Node E exists in graph; since unreachable from A, distance should remain Integer.MAX_VALUE
        assertEquals(Integer.MAX_VALUE, (int) distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths throws for null graph")
    void testFindShortestPathsNullGraph() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths throws when start node is not in graph")
    void testFindShortestPathsMissingStartNode() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("X", new HashMap<>());

        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }

    @Test
    @DisplayName("shutdown delegates to the underlying executor")
    void testShutdown() {
        dataProcessor.shutdown();
    }
}