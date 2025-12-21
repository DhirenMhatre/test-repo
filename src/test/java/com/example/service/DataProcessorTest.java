package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DataProcessor Tests")
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
        dataProcessor = null;
    }

    @Test
    @DisplayName("Should create instance successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    // processDataPipeline tests

    @Test
    @DisplayName("processDataPipeline: Should return empty map for null data")
    void testProcessDataPipeline_NullData() {
        java.util.Map<String, java.util.List<java.lang.Integer>> result =
                dataProcessor.<java.lang.String, java.lang.Integer>processDataPipeline(
                        null,
                        s -> true,
                        String::length,
                        len -> len % 2 == 0 ? "even" : "odd",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: Should return empty map for empty data")
    void testProcessDataPipeline_EmptyData() {
        java.util.Map<String, java.util.List<java.lang.Integer>> result =
                dataProcessor.<java.lang.String, java.lang.Integer>processDataPipeline(
                        new java.util.ArrayList<>(),
                        s -> true,
                        String::length,
                        len -> len % 2 == 0 ? "even" : "odd",
                        java.util.Comparator.naturalOrder()
                );
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline: Filters, transforms, sorts, groups, distincts and limits correctly")
    void testProcessDataPipeline_FullPipeline() {
        java.util.List<java.lang.String> data = java.util.Arrays.asList(
                "aa", "bbb", "cccc", "dd", "bbb", "eeee", "", "zzzz", "ttttt"
        );

        java.util.Map<java.lang.String, java.util.List<java.lang.Integer>> result =
                dataProcessor.<java.lang.String, java.lang.Integer>processDataPipeline(
                        data,
                        s -> !s.startsWith("t"),                                   // filter out "ttttt"
                        s -> s.isEmpty() ? null : s.length(),                      // map to length, drop empty via null
                        len -> len % 2 == 0 ? "even" : "odd",                      // group by parity
                        java.util.Comparator.naturalOrder()                        // sort ascending before grouping
                );

        assertNotNull(result);
        assertEquals(2, result.size());
        assertTrue(result.containsKey("even"));
        assertTrue(result.containsKey("odd"));

        java.util.List<java.lang.Integer> even = result.get("even");
        java.util.List<java.lang.Integer> odd = result.get("odd");

        // After transformation and distinct+limit:
        // even candidates: 2 ("aa"), 4 ("cccc"), 2 ("dd"), 4 ("eeee"), 4 ("zzzz") => distinct -> [2,4]
        // odd candidates: 3 ("bbb"), 3 ("bbb") => distinct -> [3]
        assertEquals(java.util.Arrays.asList(2, 4), even);
        assertEquals(java.util.Arrays.asList(3), odd);
    }

    @Test
    @DisplayName("processDataPipeline: Enforces 100 item limit per group")
    void testProcessDataPipeline_LimitPerGroup() {
        java.util.List<java.lang.Integer> data = new java.util.ArrayList<>();
        for (int i = 1; i <= 150; i++) {
            data.add(i);
        }

        java.util.Map<java.lang.String, java.util.List<java.lang.Integer>> result =
                dataProcessor.<java.lang.Integer, java.lang.Integer>processDataPipeline(
                        data,
                        v -> true,
                        java.util.function.Function.identity(),
                        v -> "all",
                        java.util.Comparator.naturalOrder()
                );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertTrue(result.containsKey("all"));
        java.util.List<java.lang.Integer> list = result.get("all");
        assertEquals(100, list.size());
        assertEquals(1, list.get(0));
        assertEquals(100, list.get(99));
    }

    // calculateStatistics tests

    @Test
    @DisplayName("calculateStatistics: Computes mean, median, quartiles, std dev and outliers correctly")
    void testCalculateStatistics_Basic() {
        java.util.List<java.lang.Double> values = java.util.Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // Expected calculations based on the implementation:
        // sorted: [1,2,3,4,5,100]
        // mean = 115/6 ≈ 19.1666667
        // median = (3+4)/2 = 3.5
        // q1 = percentile 25% index ceil(0.25*6)-1=1 => 2
        // q3 = percentile 75% index ceil(0.75*6)-1=4 => 5
        // IQR = 3, outliers > 9.5 or < -2.5 => [100]
        double expectedMean = 115.0 / 6.0;
        double expectedMedian = 3.5;
        double expectedQ1 = 2.0;
        double expectedQ3 = 5.0;

        // population variance: average of squared deviations (divide by n)
        double variance = 0.0;
        for (double v : values) {
            double d = v - expectedMean;
            variance += d * d;
        }
        variance /= values.size();
        double expectedStdDev = Math.sqrt(variance);

        assertEquals(expectedMean, result.getMean(), 1e-6);
        assertEquals(expectedMedian, result.getMedian(), 1e-6);
        assertEquals(expectedQ1, result.getQ1(), 1e-6);
        assertEquals(expectedQ3, result.getQ3(), 1e-6);
        assertEquals(expectedStdDev, result.getStandardDeviation(), 1e-6);

        java.util.List<java.lang.Double> outliers = result.getOutliers();
        assertNotNull(outliers);
        assertEquals(1, outliers.size());
        assertEquals(100.0, outliers.get(0), 1e-9);
    }

    @Test
    @DisplayName("calculateStatistics: No outliers for a simple uniform set")
    void testCalculateStatistics_NoOutliers() {
        java.util.List<java.lang.Double> values = java.util.Arrays.asList(1d, 2d, 3d, 4d);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        // mean = 2.5, median = 2.5, q1 = 1, q3 = 3
        assertEquals(2.5, result.getMean(), 1e-9);
        assertEquals(2.5, result.getMedian(), 1e-9);
        assertEquals(1.0, result.getQ1(), 1e-9);
        assertEquals(3.0, result.getQ3(), 1e-9);

        // population std dev: sqrt(((1.5^2 + 0.5^2 + 0.5^2 + 1.5^2)/4)) = sqrt(1.25) ≈ 1.1180
        assertEquals(Math.sqrt(1.25), result.getStandardDeviation(), 1e-9);

        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics: Throws for null input")
    void testCalculateStatistics_Null_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics: Throws for empty input")
    void testCalculateStatistics_Empty_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(new java.util.ArrayList<>()));
    }

    @Test
    @DisplayName("StatisticalResult: Outliers list is unmodifiable")
    void testStatisticalResult_OutliersImmutability() {
        java.util.List<java.lang.Double> values = java.util.Arrays.asList(1d, 2d, 3d, 4d, 5d, 100d);
        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);
        java.util.List<java.lang.Double> outliers = result.getOutliers();
        assertThrows(UnsupportedOperationException.class, () -> outliers.add(200d));
    }

    // processInParallel tests

    @Test
    @DisplayName("processInParallel: Processes keys in parallel and aggregates results")
    void testProcessInParallel_Success() {
        java.util.List<java.lang.String> keys = java.util.Arrays.asList("a", "bb", "ccc");

        java.util.concurrent.CompletableFuture<java.util.Map<java.lang.String, java.lang.Integer>> future =
                dataProcessor.<java.lang.Integer>processInParallel(
                        keys,
                        k -> k.length()
                );

        java.util.Map<java.lang.String, java.lang.Integer> result = future.join();
        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel: Returns empty map when keys are empty")
    void testProcessInParallel_EmptyKeys() {
        java.util.List<java.lang.String> keys = new java.util.ArrayList<>();

        java.util.concurrent.CompletableFuture<java.util.Map<java.lang.String, java.lang.Integer>> future =
                dataProcessor.<java.lang.Integer>processInParallel(
                        keys,
                        k -> k.length()
                );

        java.util.Map<java.lang.String, java.lang.Integer> result = future.join();
        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processInParallel: Propagates exceptions from processor")
    void testProcessInParallel_ExceptionPropagation() {
        java.util.List<java.lang.String> keys = java.util.Arrays.asList("ok1", "bad", "ok2");

        assertThrows(java.util.concurrent.CompletionException.class, () -> {
            dataProcessor.<java.lang.Integer>processInParallel(
                    keys,
                    k -> {
                        if ("bad".equals(k)) {
                            throw new RuntimeException("boom");
                        }
                        return k.length();
                    }
            ).join();
        });
    }

    // findShortestPaths tests

    @Test
    @DisplayName("findShortestPaths: Computes shortest paths correctly in a small graph")
    void testFindShortestPaths_ShortestPaths() {
        java.util.Map<java.lang.String, java.util.Map<java.lang.String, java.lang.Integer>> graph = new java.util.HashMap<>();

        java.util.Map<java.lang.String, java.lang.Integer> aNeighbors = new java.util.HashMap<>();
        aNeighbors.put("B", 1);
        aNeighbors.put("C", 4);

        java.util.Map<java.lang.String, java.lang.Integer> bNeighbors = new java.util.HashMap<>();
        bNeighbors.put("C", 2);
        bNeighbors.put("D", 5);

        java.util.Map<java.lang.String, java.lang.Integer> cNeighbors = new java.util.HashMap<>();
        cNeighbors.put("D", 1);

        java.util.Map<java.lang.String, java.lang.Integer> dNeighbors = new java.util.HashMap<>();

        java.util.Map<java.lang.String, java.lang.Integer> eNeighbors = new java.util.HashMap<>(); // unreachable

        graph.put("A", aNeighbors);
        graph.put("B", bNeighbors);
        graph.put("C", cNeighbors);
        graph.put("D", dNeighbors);
        graph.put("E", eNeighbors);

        java.util.Map<java.lang.String, java.lang.Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(5, distances.size());
        assertEquals(0, distances.get("A").intValue());
        assertEquals(1, distances.get("B").intValue());
        assertEquals(3, distances.get("C").intValue()); // A->B->C
        assertEquals(4, distances.get("D").intValue()); // A->B->C->D
        assertEquals(java.lang.Integer.MAX_VALUE, distances.get("E").intValue()); // unreachable
    }

    @Test
    @DisplayName("findShortestPaths: Throws for null graph")
    void testFindShortestPaths_NullGraph_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths: Throws for missing start node")
    void testFindShortestPaths_MissingStartNode_Throws() {
        java.util.Map<java.lang.String, java.util.Map<java.lang.String, java.lang.Integer>> graph = new java.util.HashMap<>();
        graph.put("X", new java.util.HashMap<>());
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}