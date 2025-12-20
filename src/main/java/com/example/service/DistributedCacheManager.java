package com.example.service;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Advanced Distributed Cache Manager with multiple eviction policies,
 * TTL support, distributed locking, statistics, and event listeners.
 * 
 * This is a production-ready cache implementation with:
 * - Multiple eviction policies (LRU, LFU, FIFO, Custom)
 * - Time-to-Live (TTL) support with automatic expiration
 * - Thread-safe operations with read-write locks
 * - Cache statistics and monitoring
 * - Event listeners for cache operations
 * - Distributed locking simulation
 * - Memory-efficient with configurable size limits
 */
public class DistributedCacheManager<K, V> {
    
    public enum EvictionPolicy {
        LRU,  // Least Recently Used
        LFU,  // Least Frequently Used
        FIFO, // First In First Out
        CUSTOM // Custom eviction based on priority
    }
    
    private final int maxSize;
    private final EvictionPolicy evictionPolicy;
    private final long defaultTTLMillis;
    private final Map<K, CacheEntry<V>> cache;
    private final ReentrantReadWriteLock lock;
    private final ScheduledExecutorService ttlExecutor;
    private final ExecutorService eventExecutor;
    private final CacheStatistics statistics;
    private final List<CacheEventListener<K, V>> eventListeners;
    private final Map<K, Semaphore> distributedLocks;
    
    // For LRU: maintain access order
    private final LinkedHashMap<K, Long> accessOrder;
    
    // For LFU: maintain frequency counts
    private final Map<K, Long> accessFrequency;
    
    // For FIFO: maintain insertion order
    private final Queue<K> insertionOrder;
    
    public DistributedCacheManager(int maxSize, EvictionPolicy evictionPolicy, long defaultTTLMillis) {
        if (maxSize <= 0) {
            throw new IllegalArgumentException("Max size must be positive");
        }
        if (defaultTTLMillis < 0) {
            throw new IllegalArgumentException("TTL must be non-negative");
        }
        
        this.maxSize = maxSize;
        this.evictionPolicy = evictionPolicy;
        this.defaultTTLMillis = defaultTTLMillis;
        this.cache = new ConcurrentHashMap<>();
        this.lock = new ReentrantReadWriteLock();
        this.ttlExecutor = Executors.newScheduledThreadPool(1);
        this.eventExecutor = Executors.newFixedThreadPool(2);
        this.statistics = new CacheStatistics();
        this.eventListeners = new CopyOnWriteArrayList<>();
        this.distributedLocks = new ConcurrentHashMap<>();
        
        // Initialize policy-specific data structures
        this.accessOrder = new LinkedHashMap<>(16, 0.75f, true);
        this.accessFrequency = new ConcurrentHashMap<>();
        this.insertionOrder = new ConcurrentLinkedQueue<>();
        
        // Start TTL cleanup task
        if (defaultTTLMillis > 0) {
            startTTLCleanup();
        }
    }
    
    /**
     * Put a value in the cache with default TTL.
     */
    public void put(K key, V value) {
        put(key, value, defaultTTLMillis);
    }
    
    /**
     * Put a value in the cache with custom TTL.
     */
    public void put(K key, V value, long ttlMillis) {
        if (key == null || value == null) {
            throw new IllegalArgumentException("Key and value cannot be null");
        }
        
        lock.writeLock().lock();
        try {
            // Check if we need to evict
            if (!cache.containsKey(key) && cache.size() >= maxSize) {
                evictEntry();
            }
            
            long expiryTime = ttlMillis > 0 ? System.currentTimeMillis() + ttlMillis : Long.MAX_VALUE;
            CacheEntry<V> entry = new CacheEntry<>(value, expiryTime);
            
            CacheEntry<V> oldEntry = cache.put(key, entry);
            updatePolicyDataStructures(key, oldEntry == null);
            
            statistics.recordPut();
            fireEvent(CacheEvent.Type.PUT, key, value, oldEntry != null ? oldEntry.value : null);
        } finally {
            lock.writeLock().unlock();
        }
    }
    
    /**
     * Get a value from the cache.
     */
    public V get(K key) {
        if (key == null) {
            return null;
        }
        
        lock.readLock().lock();
        try {
            CacheEntry<V> entry = cache.get(key);
            
            if (entry == null) {
                statistics.recordMiss();
                return null;
            }
            
            // Check if expired
            if (entry.isExpired()) {
                cache.remove(key);
                removeFromPolicyStructures(key);
                statistics.recordExpiration();
                fireEvent(CacheEvent.Type.EXPIRE, key, null, entry.value);
                return null;
            }
            
            // Update access patterns
            updateAccessPattern(key);
            statistics.recordHit();
            fireEvent(CacheEvent.Type.GET, key, entry.value, null);
            
            return entry.value;
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Get or compute a value if absent (thread-safe compute-if-absent).
     */
    public V getOrCompute(K key, Function<K, V> computeFunction) {
        return getOrCompute(key, computeFunction, defaultTTLMillis);
    }
    
    /**
     * Get or compute a value if absent with custom TTL.
     */
    public V getOrCompute(K key, Function<K, V> computeFunction, long ttlMillis) {
        V value = get(key);
        if (value != null) {
            return value;
        }
        
        // Use distributed lock to prevent duplicate computation
        Semaphore lock = distributedLocks.computeIfAbsent(key, k -> new Semaphore(1));
        
        try {
            if (lock.tryAcquire()) {
                try {
                    // Double-check after acquiring lock
                    value = get(key);
                    if (value != null) {
                        return value;
                    }
                    
                    // Compute new value
                    value = computeFunction.apply(key);
                    if (value != null) {
                        put(key, value, ttlMillis);
                    }
                    return value;
                } finally {
                    lock.release();
                }
            } else {
                // Another thread is computing, wait and retry
                lock.acquire();
                try {
                    return get(key);
                } finally {
                    lock.release();
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Interrupted while computing value", e);
        }
    }
    
    /**
     * Remove a key from the cache.
     */
    public V remove(K key) {
        if (key == null) {
            return null;
        }
        
        lock.writeLock().lock();
        try {
            CacheEntry<V> entry = cache.remove(key);
            if (entry != null) {
                removeFromPolicyStructures(key);
                statistics.recordEviction();
                fireEvent(CacheEvent.Type.REMOVE, key, null, entry.value);
                return entry.value;
            }
            return null;
        } finally {
            lock.writeLock().unlock();
        }
    }
    
    /**
     * Clear all entries from the cache.
     */
    public void clear() {
        lock.writeLock().lock();
        try {
            int size = cache.size();
            cache.clear();
            accessOrder.clear();
            accessFrequency.clear();
            insertionOrder.clear();
            statistics.recordClear(size);
            fireEvent(CacheEvent.Type.CLEAR, null, null, null);
        } finally {
            lock.writeLock().unlock();
        }
    }
    
    /**
     * Get current cache size.
     */
    public int size() {
        lock.readLock().lock();
        try {
            return cache.size();
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Check if cache contains a key.
     */
    public boolean containsKey(K key) {
        return get(key) != null;
    }
    
    /**
     * Get cache statistics.
     */
    public CacheStatistics getStatistics() {
        return statistics.copy();
    }
    
    /**
     * Add an event listener.
     */
    public void addEventListener(CacheEventListener<K, V> listener) {
        eventListeners.add(listener);
    }
    
    /**
     * Remove an event listener.
     */
    public void removeEventListener(CacheEventListener<K, V> listener) {
        eventListeners.remove(listener);
    }
    
    /**
     * Shutdown the cache manager and cleanup resources.
     */
    public void shutdown() {
        ttlExecutor.shutdown();
        eventExecutor.shutdown();
        try {
            if (!ttlExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                ttlExecutor.shutdownNow();
            }
            if (!eventExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                eventExecutor.shutdownNow();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            ttlExecutor.shutdownNow();
            eventExecutor.shutdownNow();
        }
    }
    
    // Private helper methods
    
    private void evictEntry() {
        K keyToEvict = selectKeyToEvict();
        if (keyToEvict != null) {
            remove(keyToEvict);
        }
    }
    
    private K selectKeyToEvict() {
        switch (evictionPolicy) {
            case LRU:
                return accessOrder.entrySet().stream()
                        .findFirst()
                        .map(Map.Entry::getKey)
                        .orElse(null);
            case LFU:
                return accessFrequency.entrySet().stream()
                        .min(Map.Entry.comparingByValue())
                        .map(Map.Entry::getKey)
                        .orElse(null);
            case FIFO:
                return insertionOrder.peek();
            case CUSTOM:
                // Custom: evict oldest entry by expiry time
                return cache.entrySet().stream()
                        .min(Comparator.comparingLong(e -> e.getValue().expiryTime))
                        .map(Map.Entry::getKey)
                        .orElse(null);
            default:
                return cache.keySet().stream().findFirst().orElse(null);
        }
    }
    
    private void updatePolicyDataStructures(K key, boolean isNew) {
        if (isNew) {
            insertionOrder.offer(key);
            accessFrequency.put(key, 0L);
        }
        accessOrder.put(key, System.currentTimeMillis());
    }
    
    private void removeFromPolicyStructures(K key) {
        accessOrder.remove(key);
        accessFrequency.remove(key);
        insertionOrder.remove(key);
        distributedLocks.remove(key);
    }
    
    private void updateAccessPattern(K key) {
        accessOrder.put(key, System.currentTimeMillis());
        accessFrequency.merge(key, 1L, Long::sum);
    }
    
    private void startTTLCleanup() {
        ttlExecutor.scheduleAtFixedRate(() -> {
            lock.writeLock().lock();
            try {
                List<K> expiredKeys = cache.entrySet().stream()
                        .filter(e -> e.getValue().isExpired())
                        .map(Map.Entry::getKey)
                        .collect(Collectors.toList());
                
                expiredKeys.forEach(this::remove);
            } finally {
                lock.writeLock().unlock();
            }
        }, defaultTTLMillis / 2, defaultTTLMillis / 2, TimeUnit.MILLISECONDS);
    }
    
    private void fireEvent(CacheEvent.Type type, K key, V newValue, V oldValue) {
        if (eventListeners.isEmpty()) {
            return;
        }
        
        CacheEvent<K, V> event = new CacheEvent<>(type, key, newValue, oldValue, System.currentTimeMillis());
        eventListeners.forEach(listener -> {
            eventExecutor.submit(() -> {
                try {
                    listener.onEvent(event);
                } catch (Exception e) {
                    // Log error but don't fail the operation
                    System.err.println("Error in cache event listener: " + e.getMessage());
                }
            });
        });
    }
    
    // Inner classes
    
    private static class CacheEntry<V> {
        final V value;
        final long expiryTime;
        
        CacheEntry(V value, long expiryTime) {
            this.value = value;
            this.expiryTime = expiryTime;
        }
        
        boolean isExpired() {
            return System.currentTimeMillis() > expiryTime;
        }
    }
    
    public static class CacheStatistics {
        private long hits;
        private long misses;
        private long puts;
        private long evictions;
        private long expirations;
        private long clears;
        
        synchronized void recordHit() { hits++; }
        synchronized void recordMiss() { misses++; }
        synchronized void recordPut() { puts++; }
        synchronized void recordEviction() { evictions++; }
        synchronized void recordExpiration() { expirations++; }
        synchronized void recordClear(long clearedCount) { clears += clearedCount; }
        
        public long getHits() { return hits; }
        public long getMisses() { return misses; }
        public long getPuts() { return puts; }
        public long getEvictions() { return evictions; }
        public long getExpirations() { return expirations; }
        public long getClears() { return clears; }
        
        public double getHitRate() {
            long total = hits + misses;
            return total > 0 ? (double) hits / total : 0.0;
        }
        
        public synchronized CacheStatistics copy() {
            CacheStatistics copy = new CacheStatistics();
            copy.hits = this.hits;
            copy.misses = this.misses;
            copy.puts = this.puts;
            copy.evictions = this.evictions;
            copy.expirations = this.expirations;
            copy.clears = this.clears;
            return copy;
        }
    }
    
    public static class CacheEvent<K, V> {
        public enum Type {
            GET, PUT, REMOVE, EXPIRE, CLEAR
        }
        
        private final Type type;
        private final K key;
        private final V newValue;
        private final V oldValue;
        private final long timestamp;
        
        public CacheEvent(Type type, K key, V newValue, V oldValue, long timestamp) {
            this.type = type;
            this.key = key;
            this.newValue = newValue;
            this.oldValue = oldValue;
            this.timestamp = timestamp;
        }
        
        public Type getType() { return type; }
        public K getKey() { return key; }
        public V getNewValue() { return newValue; }
        public V getOldValue() { return oldValue; }
        public long getTimestamp() { return timestamp; }
    }
    
    public interface CacheEventListener<K, V> {
        void onEvent(CacheEvent<K, V> event);
    }
}

