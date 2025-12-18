package com.example.service;

import java.util.*;
import java.util.stream.Collectors;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Function;
import java.util.function.Predicate;

/**
 * Advanced data processing service with complex algorithms for data transformation,
 * filtering, aggregation, and parallel processing.
 */
public class DataProcessor {
    
    private final ExecutorService executorService;
    private final Map<String, ProcessingStrategy> strategies;
    
    public DataProcessor() {
        this.executorService = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());
        this.strategies = initializeStrategies();
    }
    
    /**
     * Processes a collection of data items with complex transformation pipeline.
     * Includes filtering, mapping, grouping, and statistical calculations.
     */
    public <T, R> Map<String, List<R>> processDataPipeline(
            List<T> data,
            Predicate<T> filter,
            Function<T, R> transformer,
            Function<R, String> grouper,
            Comparator<R> sorter) {
        
        if (data == null || data.isEmpty()) {
            return Collections.emptyMap();
        }
        
        return data.stream()
                .filter(filter)
                .map(transformer)
                .filter(Objects::nonNull)
                .sorted(sorter)
                .collect(Collectors.groupingBy(
                    grouper,
                    Collectors.collectingAndThen(
                        Collectors.toList(),
                        list -> {
                            // Apply deduplication and limit per group
                            return list.stream()
                                    .distinct()
                                    .limit(100)
                                    .collect(Collectors.toList());
                        }
                    )
                ));
    }
    
    /**
     * Advanced statistical analysis with percentile calculations and outlier detection.
     */
    public StatisticalResult calculateStatistics(List<Double> values) {
        if (values == null || values.isEmpty()) {
            throw new IllegalArgumentException("Values list cannot be null or empty");
        }
        
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        
        double mean = sorted.stream().mapToDouble(Double::doubleValue).average().orElse(0.0);
        double median = calculateMedian(sorted);
        double q1 = calculatePercentile(sorted, 25);
        double q3 = calculatePercentile(sorted, 75);
        double iqr = q3 - q1;
        
        // Outlier detection using IQR method
        double lowerBound = q1 - 1.5 * iqr;
        double upperBound = q3 + 1.5 * iqr;
        List<Double> outliers = sorted.stream()
                .filter(v -> v < lowerBound || v > upperBound)
                .collect(Collectors.toList());
        
        // Standard deviation
        double variance = sorted.stream()
                .mapToDouble(v -> Math.pow(v - mean, 2))
                .average()
                .orElse(0.0);
        double stdDev = Math.sqrt(variance);
        
        return new StatisticalResult(mean, median, q1, q3, stdDev, outliers);
    }
    
    /**
     * Parallel processing with async operations and result aggregation.
     */
    public <T> CompletableFuture<Map<String, T>> processInParallel(
            List<String> keys,
            Function<String, T> processor) {
        
        List<CompletableFuture<Map.Entry<String, T>>> futures = keys.stream()
                .map(key -> CompletableFuture.supplyAsync(() -> {
                    try {
                        T result = processor.apply(key);
                        return new AbstractMap.SimpleEntry<>(key, result);
                    } catch (Exception e) {
                        throw new RuntimeException("Processing failed for key: " + key, e);
                    }
                }, executorService))
                .collect(Collectors.toList());
        
        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
                .thenApply(v -> futures.stream()
                        .map(CompletableFuture::join)
                        .collect(Collectors.toMap(
                            Map.Entry::getKey,
                            Map.Entry::getValue,
                            (existing, replacement) -> existing
                        )));
    }
    
    /**
     * Complex graph-based path finding algorithm (simplified Dijkstra-like).
     */
    public Map<String, Integer> findShortestPaths(
            Map<String, Map<String, Integer>> graph,
            String startNode) {
        
        if (graph == null || !graph.containsKey(startNode)) {
            throw new IllegalArgumentException("Invalid graph or start node");
        }
        
        Map<String, Integer> distances = new HashMap<>();
        Set<String> visited = new HashSet<>();
        PriorityQueue<NodeDistance> queue = new PriorityQueue<>(Comparator.comparingInt(nd -> nd.distance));
        
        // Initialize distances
        graph.keySet().forEach(node -> distances.put(node, Integer.MAX_VALUE));
        distances.put(startNode, 0);
        queue.offer(new NodeDistance(startNode, 0));
        
        while (!queue.isEmpty()) {
            NodeDistance current = queue.poll();
            if (visited.contains(current.node)) {
                continue;
            }
            visited.add(current.node);
            
            Map<String, Integer> neighbors = graph.getOrDefault(current.node, Collections.emptyMap());
            for (Map.Entry<String, Integer> neighbor : neighbors.entrySet()) {
                if (!visited.contains(neighbor.getKey())) {
                    int newDistance = current.distance + neighbor.getValue();
                    if (newDistance < distances.get(neighbor.getKey())) {
                        distances.put(neighbor.getKey(), newDistance);
                        queue.offer(new NodeDistance(neighbor.getKey(), newDistance));
                    }
                }
            }
        }
        
        return distances;
    }
    
    private double calculateMedian(List<Double> sorted) {
        int size = sorted.size();
        if (size % 2 == 0) {
            return (sorted.get(size / 2 - 1) + sorted.get(size / 2)) / 2.0;
        } else {
            return sorted.get(size / 2);
        }
    }
    
    private double calculatePercentile(List<Double> sorted, double percentile) {
        if (percentile < 0 || percentile > 100) {
            throw new IllegalArgumentException("Percentile must be between 0 and 100");
        }
        int index = (int) Math.ceil((percentile / 100.0) * sorted.size()) - 1;
        return sorted.get(Math.max(0, Math.min(index, sorted.size() - 1)));
    }
    
    private Map<String, ProcessingStrategy> initializeStrategies() {
        Map<String, ProcessingStrategy> strategies = new HashMap<>();
        strategies.put("default", new DefaultStrategy());
        strategies.put("optimized", new OptimizedStrategy());
        strategies.put("memory-efficient", new MemoryEfficientStrategy());
        return strategies;
    }
    
    public void shutdown() {
        executorService.shutdown();
    }
    
    // Inner classes for complex logic organization
    private static class NodeDistance {
        final String node;
        final int distance;
        
        NodeDistance(String node, int distance) {
            this.node = node;
            this.distance = distance;
        }
    }
    
    public static class StatisticalResult {
        private final double mean;
        private final double median;
        private final double q1;
        private final double q3;
        private final double standardDeviation;
        private final List<Double> outliers;
        
        public StatisticalResult(double mean, double median, double q1, double q3, 
                                double standardDeviation, List<Double> outliers) {
            this.mean = mean;
            this.median = median;
            this.q1 = q1;
            this.q3 = q3;
            this.standardDeviation = standardDeviation;
            this.outliers = Collections.unmodifiableList(new ArrayList<>(outliers));
        }
        
        // Getters
        public double getMean() { return mean; }
        public double getMedian() { return median; }
        public double getQ1() { return q1; }
        public double getQ3() { return q3; }
        public double getStandardDeviation() { return standardDeviation; }
        public List<Double> getOutliers() { return outliers; }
    }
    
    // Strategy pattern implementation
    private interface ProcessingStrategy {
        <T> List<T> process(List<T> data);
    }
    
    private static class DefaultStrategy implements ProcessingStrategy {
        @Override
        public <T> List<T> process(List<T> data) {
            return new ArrayList<>(data);
        }
    }
    
    private static class OptimizedStrategy implements ProcessingStrategy {
        @Override
        public <T> List<T> process(List<T> data) {
            return data.stream()
                    .distinct()
                    .collect(Collectors.toList());
        }
    }
    
    private static class MemoryEfficientStrategy implements ProcessingStrategy {
        @Override
        public <T> List<T> process(List<T> data) {
            return data.stream()
                    .filter(Objects::nonNull)
                    .limit(1000)
                    .collect(Collectors.toList());
        }
    }
}

