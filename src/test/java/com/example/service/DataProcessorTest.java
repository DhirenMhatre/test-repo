package com.example.service;

import com.example.service.DataProcessor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.function.Predicate;

@DisplayName("DataProcessor Tests")
class DataProcessorTest {

    private static final double DELTA = 1e-9;

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
    @DisplayName("Constructor should create instance successfully")
    void testConstructor() {
        assertNotNull(dataProcessor);
    }

    // ----------------------------
    // processDataPipeline
    // ----------------------------

    @Test
    @DisplayName("processDataPipeline should return empty map for null input data")
    void testProcessDataPipeline_NullData_ReturnsEmptyMap() {
        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                null,
                s -> true,
                String::length,
                len -> "all",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline should return empty map for empty input data")
    void testProcessDataPipeline_EmptyData_ReturnsEmptyMap() {
        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                Collections.emptyList(),
                s -> true,
                String::length,
                len -> "all",
                Comparator.naturalOrder()
        );

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("processDataPipeline should filter, transform, sort, group and deduplicate; null transformed values are removed")
    void testProcessDataPipeline_FilterTransformSortGroupDistinctAndRemoveNulls() {
        List<String> input = Arrays.asList("a", "bb", "ccc", "dddd", "x", "ee", "yyy");

        Predicate<String> filter = s -> s.length() >= 2;
        Function<String, Integer> transformer = s -> {
            if ("ee".equals(s)) {
                return null; // verify nulls are filtered after mapping
            }
            return s.length();
        };
        Function<Integer, String> grouper = len -> (len % 2 == 0) ? "even" : "odd";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                input, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        assertTrue(result.containsKey("odd"));
        assertTrue(result.containsKey("even"));

        // Filtered items: "bb"(2), "ccc"(3), "dddd"(4), "ee"(null), "yyy"(3)
        // After null removal: 2,3,4,3 -> sorted: 2,3,3,4 -> group distinct within group:
        // even: [2,4] (in that order because sorted globally then grouped)
        // odd: [3]
        assertEquals(Arrays.asList(2, 4), result.get("even"));
        assertEquals(Collections.singletonList(3), result.get("odd"));
    }

    @Test
    @DisplayName("processDataPipeline should limit each group to 100 distinct elements")
    void testProcessDataPipeline_GroupLimit100() {
        List<Integer> input = new ArrayList<>();
        for (int i = 1; i <= 250; i++) {
            input.add(i);
        }

        Predicate<Integer> filter = v -> true;
        Function<Integer, Integer> transformer = v -> v;
        Function<Integer, String> grouper = v -> "g";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<Integer, Integer>processDataPipeline(
                input, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertTrue(result.containsKey("g"));
        assertEquals(100, result.get("g").size());
        assertEquals(1, result.get("g").get(0));
        assertEquals(100, result.get("g").get(99));
    }

    @Test
    @DisplayName("processDataPipeline distinct should remove duplicates inside each group even if input contains many duplicates")
    void testProcessDataPipeline_DistinctPerGroup() {
        List<String> input = Arrays.asList("aa", "bb", "cc", "dd", "ee", "ff");

        Predicate<String> filter = s -> true;
        Function<String, Integer> transformer = s -> 2; // everything maps to same value
        Function<Integer, String> grouper = v -> "g";
        Comparator<Integer> sorter = Comparator.naturalOrder();

        Map<String, List<Integer>> result = dataProcessor.<String, Integer>processDataPipeline(
                input, filter, transformer, grouper, sorter
        );

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(Collections.singletonList(2), result.get("g"));
    }

    // ----------------------------
    // calculateStatistics
    // ----------------------------

    @Test
    @DisplayName("calculateStatistics should throw IllegalArgumentException for null list")
    void testCalculateStatistics_Null_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(null));
    }

    @Test
    @DisplayName("calculateStatistics should throw IllegalArgumentException for empty list")
    void testCalculateStatistics_Empty_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.calculateStatistics(Collections.emptyList()));
    }

    @Test
    @DisplayName("calculateStatistics should compute mean/median/quartiles/stddev for odd-sized list with no outliers")
    void testCalculateStatistics_OddCount_NoOutliers() {
        // Sorted: [1,2,3,4,5]
        // mean = 3
        // median = 3
        // q1 = percentile 25 -> ceil(0.25*5)=2 -> index 1 -> 2
        // q3 = percentile 75 -> ceil(0.75*5)=4 -> index 3 -> 4
        // iqr=2, bounds [-1,7], outliers none
        // variance = avg((x-3)^2) = (4+1+0+1+4)/5 = 2, stddev=sqrt(2)
        List<Double> values = Arrays.asList(5.0, 1.0, 4.0, 2.0, 3.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(3.0, result.getMean(), DELTA);
        assertEquals(3.0, result.getMedian(), DELTA);
        assertEquals(2.0, result.getQ1(), DELTA);
        assertEquals(4.0, result.getQ3(), DELTA);
        assertEquals(Math.sqrt(2.0), result.getStandardDeviation(), 1e-12);
        assertNotNull(result.getOutliers());
        assertTrue(result.getOutliers().isEmpty());
    }

    @Test
    @DisplayName("calculateStatistics should compute median for even-sized list")
    void testCalculateStatistics_EvenCount_MedianAverageOfMiddleTwo() {
        // Sorted: [1,2,3,4]
        // median=(2+3)/2=2.5
        List<Double> values = Arrays.asList(4.0, 1.0, 3.0, 2.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result);
        assertEquals(2.5, result.getMedian(), DELTA);
    }

    @Test
    @DisplayName("calculateStatistics percentile edge cases: q1 and q3 follow ceil-based index selection")
    void testCalculateStatistics_Quartiles_CeilIndexDefinition() {
        // Sorted: [10,20,30,40]
        // q1: ceil(0.25*4)=1 => idx 0 => 10
        // q3: ceil(0.75*4)=3 => idx 2 => 30
        List<Double> values = Arrays.asList(40.0, 10.0, 30.0, 20.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertEquals(10.0, result.getQ1(), DELTA);
        assertEquals(30.0, result.getQ3(), DELTA);
    }

    @Test
    @DisplayName("calculateStatistics should detect outliers using IQR method")
    void testCalculateStatistics_OutliersDetected() {
        // Sorted: [1,2,3,4,100]
        // q1=2, q3=4, iqr=2 => bounds [-1, 7] => outlier [100]
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertNotNull(result.getOutliers());
        assertEquals(1, result.getOutliers().size());
        assertEquals(100.0, result.getOutliers().get(0), DELTA);
    }

    @Test
    @DisplayName("calculateStatistics should return outliers list as unmodifiable")
    void testCalculateStatistics_OutliersListUnmodifiable() {
        List<Double> values = Arrays.asList(1.0, 2.0, 3.0, 4.0, 100.0);

        DataProcessor.StatisticalResult result = dataProcessor.calculateStatistics(values);

        assertThrows(UnsupportedOperationException.class, () -> result.getOutliers().add(200.0));
    }

    // ----------------------------
    // processInParallel
    // ----------------------------

    @Test
    @DisplayName("processInParallel should process keys and return map of results")
    void testProcessInParallel_Success() throws Exception {
        List<String> keys = Arrays.asList("a", "bb", "ccc");
        Function<String, Integer> processor = String::length;

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, processor);
        Map<String, Integer> result = future.get(2, TimeUnit.SECONDS);

        assertNotNull(result);
        assertEquals(3, result.size());
        assertEquals(1, result.get("a"));
        assertEquals(2, result.get("bb"));
        assertEquals(3, result.get("ccc"));
    }

    @Test
    @DisplayName("processInParallel should keep first value when duplicate keys are present")
    void testProcessInParallel_DuplicateKeys_KeepsExisting() throws Exception {
        List<String> keys = Arrays.asList("k", "k", "k");
        Function<String, Integer> processor = s -> 1; // same value anyway, but ensures merge function doesn't blow up

        CompletableFuture<Map<String, Integer>> future = dataProcessor.processInParallel(keys, processor);
        Map<String, Integer> result = future.get(2, TimeUnit.SECONDS);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(1, result.get("k"));
    }

    @Test
    @DisplayName("processInParallel should complete exceptionally when processor throws, wrapping with RuntimeException message including key")
    void testProcessInParallel_ProcessorThrows_CompletesExceptionally() {
        List<String> keys = Arrays.asList("ok", "bad", "later");
        Function<String, String> processor = k -> {
            if ("bad".equals(k)) {
                throw new IllegalStateException("boom");
            }
            return k.toUpperCase();
        };

        CompletableFuture<Map<String, String>> future = dataProcessor.processInParallel(keys, processor);

        ExecutionException ex = assertThrows(ExecutionException.class, () -> future.get(2, TimeUnit.SECONDS));
        assertNotNull(ex.getCause());
        assertTrue(ex.getCause() instanceof RuntimeException);
        assertTrue(ex.getCause().getMessage().contains("Processing failed for key: bad"));
        assertNotNull(ex.getCause().getCause());
        assertTrue(ex.getCause().getCause() instanceof IllegalStateException);
    }

    // ----------------------------
    // findShortestPaths
    // ----------------------------

    @Test
    @DisplayName("findShortestPaths should throw IllegalArgumentException for null graph")
    void testFindShortestPaths_NullGraph_Throws() {
        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(null, "A"));
    }

    @Test
    @DisplayName("findShortestPaths should throw IllegalArgumentException when start node not in graph")
    void testFindShortestPaths_StartNodeMissing_Throws() {
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        graph.put("A", Collections.singletonMap("B", 1));

        assertThrows(IllegalArgumentException.class, () -> dataProcessor.findShortestPaths(graph, "Z"));
    }

    @Test
    @DisplayName("findShortestPaths should compute shortest distances for reachable and unreachable nodes")
    void testFindShortestPaths_ComputesDistances() {
        // Graph:
        // A -> B (1), C (4)
        // B -> C (2), D (5)
        // C -> D (1)
        // D -> (none)
        // E isolated
        Map<String, Map<String, Integer>> graph = new HashMap<>();

        Map<String, Integer> aNeighbors = new HashMap<>();
        aNeighbors.put("B", 1);
        aNeighbors.put("C", 4);
        graph.put("A", aNeighbors);

        Map<String, Integer> bNeighbors = new HashMap<>();
        bNeighbors.put("C", 2);
        bNeighbors.put("D", 5);
        graph.put("B", bNeighbors);

        Map<String, Integer> cNeighbors = new HashMap<>();
        cNeighbors.put("D", 1);
        graph.put("C", cNeighbors);

        graph.put("D", Collections.emptyMap());
        graph.put("E", Collections.emptyMap()); // unreachable from A

        Map<String, Integer> distances = dataProcessor.findShortestPaths(graph, "A");

        assertNotNull(distances);
        assertEquals(0, distances.get("A"));
        assertEquals(1, distances.get("B"));
        assertEquals(3, distances.get("C")); // A->B->C = 1+2=3 (better than direct 4)
        assertEquals(4, distances.get("D")); // A->B->C->D = 1+2+1=4
        assertEquals(Integer.MAX_VALUE, distances.get("E"));
    }

    @Test
    @DisplayName("findShortestPaths should handle graph entries that reference neighbor nodes not present in graph by throwing NullPointerException")
    void testFindShortestPaths_NeighborNotInGraph_ThrowsNPE() {
        // The implementation initializes distances only for graph.keySet().
        // If a neighbor key isn't in graph.keySet(), distances.get(neighbor) returns null and causes NPE on comparison.
        Map<String, Map<String, Integer>> graph = new HashMap<>();
        Map<String, Integer> aNeighbors = new HashMap<>();
        aNeighbors.put("B", 1); // B not present as a key in graph
        graph.put("A", aNeighbors);

        assertThrows(NullPointerException.class, () -> dataProcessor.findShortestPaths(graph, "A"));
    }
}