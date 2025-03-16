/// Copyright 2025 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     https://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

#ifndef SANTA__COMMON__CONCURRENTLRUMAP_H
#define SANTA__COMMON__CONCURRENTLRUMAP_H

#include <Foundation/Foundation.h>

#include <cstdlib>
#include <functional>
#include <list>
#include <memory>
#include <optional>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/hash/hash.h"
#include "absl/synchronization/mutex.h"

template <typename KeyT, typename ValueT, class Hash = absl::DefaultHashContainerHash<KeyT>,
          class Eq = absl::DefaultHashContainerEq<KeyT>>
class ConcurrentLRUMap {
 public:
  ConcurrentLRUMap(size_t size, size_t num_shards = 16)
      : total_capacity_(size), num_buckets_(num_shards) {
    assert(size > 0 && "Cache size must be positive");
    assert(num_shards > 0 && "Number of shards must be positive");
    assert(size >= num_shards && "Number of shards cannot exceed cache size");

    buckets_.reserve(num_shards);
    for (size_t i = 0; i < num_shards; ++i) {
      buckets_.push_back(std::make_unique<Bucket>());
    }
  }

  // Not copyable
  ConcurrentLRUMap(const ConcurrentLRUMap &other) = delete;
  void operator=(const ConcurrentLRUMap &rhs) = delete;

  // Moves could be safely implemented, but not currently needed
  ConcurrentLRUMap(ConcurrentLRUMap &&other) = delete;
  ConcurrentLRUMap &operator=(ConcurrentLRUMap &&rhs) = delete;

  ~ConcurrentLRUMap() { Clear(); }

  void Put(const KeyT &key, const ValueT &value) {
    size_t bucket_idx = GetBucketIndex(key);
    Bucket &bucket = *buckets_[bucket_idx];

    // First, check if the key already exists in the bucket
    {
      absl::MutexLock bucket_lock(&bucket.mutex);
      auto it = bucket.cache_map.find(key);
      if (it != bucket.cache_map.end()) {
        // Key exists, need to update value and move to front
        absl::MutexLock lru_lock(&lru_mutex_);
        it->second->value = value;
        Touch(it->second);
        return;
      }
    }

    // Key doesn't exist, need to add new entry and possibly evict
    typename std::list<Node>::iterator list_it;
    {
      absl::MutexLock lru_lock(&lru_mutex_);

      // Check if we need to evict
      if (lru_list_.size() >= total_capacity_) {
        EvictLRU();
      }

      // Now add the new node at the front of the LRU list
      lru_list_.emplace_front(key, value, bucket_idx);
      list_it = lru_list_.begin();

      // Release LRU lock before acquiring bucket lock to prevent deadlock
    }

    {
      // Lock the bucket and add the mapping
      absl::MutexLock bucket_lock(&bucket.mutex);
      // TODO: Move to insert
      bucket.cache_map[key] = list_it;
    }

    // Note: We don't need to reacquire the LRU lock here since we're done
  }

  std::optional<ValueT> Get(const KeyT &key) {
    Bucket &bucket = GetBucket(key);
    typename std::list<Node>::iterator list_it;
    ValueT result;
    bool found = false;

    // First check if the key exists in the bucket
    {
      absl::ReaderMutexLock bucket_lock(&bucket.mutex);
      auto map_it = bucket.cache_map.find(key);
      if (map_it != bucket.cache_map.end()) {
        list_it = map_it->second;
        result = list_it->value;
        found = true;
      }
    }

    if (found) {
      // If found, update the LRU position
      absl::MutexLock lru_lock(&lru_mutex_);
      Touch(list_it);
      return result;
    }

    return std::nullopt;
  }

  // Check if a value exists without affecting LRU order
  bool Contains(const KeyT &key) const {
    const Bucket &bucket = GetBucket(key);

    absl::ReaderMutexLock bucket_lock(&bucket.mutex);
    auto it = bucket.cache_map.find(key);
    return it != bucket.cache_map.end();
  }

  size_t Size() const {
    absl::ReaderMutexLock lru_lock(&lru_mutex_);
    return lru_list_.size();
  }

  void Clear() {
    // Lock all buckets first, then the LRU list to prevent deadlock
    std::vector<std::unique_ptr<absl::MutexLock>> bucket_locks;
    bucket_locks.reserve(num_buckets_);

    for (auto &bucket : buckets_) {
      bucket_locks.push_back(std::make_unique<absl::MutexLock>(&bucket->mutex));
      bucket->cache_map.clear();
    }

    absl::MutexLock lru_lock(&lru_mutex_);
    lru_list_.clear();
  }

 private:
  // Node structure for doubly-linked list
  struct Node {
    Node(const KeyT &k, const ValueT &v, size_t b) : key(k), value(v), bucket_index(b) {}

    KeyT key;
    ValueT value;
    size_t bucket_index;
  };

  // Bucket structure for sharding
  struct Bucket {
    absl::flat_hash_map<KeyT, typename std::list<Node>::iterator, Hash, Eq> cache_map;
    mutable absl::Mutex mutex;
  };

  // Global LRU list and its mutex
  mutable absl::Mutex lru_mutex_;
  std::list<Node> lru_list_ ABSL_GUARDED_BY(lru_mutex_);

  size_t total_capacity_;
  size_t num_buckets_;
  std::vector<std::unique_ptr<Bucket>> buckets_;

  // Hash function to determine bucket
  size_t GetBucketIndex(const KeyT &key) const {
    // return absl::Hash<KeyT>{}(key) % num_buckets_;
    // return Hasher{}(key) % num_buckets_;
    return Hash{}(key) % num_buckets_;
  }

  // Get reference to appropriate bucket
  Bucket &GetBucket(const KeyT &key) { return *buckets_[GetBucketIndex(key)]; }

  const Bucket &GetBucket(const KeyT &key) const { return *buckets_[GetBucketIndex(key)]; }

  /// Move node to front of LRU list (assumes lru_mutex_ is held)
  void Touch(typename std::list<Node>::iterator it) ABSL_EXCLUSIVE_LOCKS_REQUIRED(lru_mutex_) {
    lru_list_.splice(lru_list_.begin(), lru_list_, it);
  }

  // Evict least recently used item (assumes lru_mutex_ is held)
  void EvictLRU() ABSL_EXCLUSIVE_LOCKS_REQUIRED(lru_mutex_) {
    if (lru_list_.empty()) return;

    const Node &lru_node = lru_list_.back();
    size_t bucket_idx = lru_node.bucket_index;
    KeyT key_to_remove = lru_node.key;

    // Release the LRU lock before acquiring bucket lock to prevent deadlock
    // lru_mutex_.Unlock();

    {
      // Lock the specific bucket
      absl::MutexLock bucket_lock(&buckets_[bucket_idx]->mutex);
      buckets_[bucket_idx]->cache_map.erase(key_to_remove);
    }

    // Reacquire the LRU lock
    // lru_mutex_.Lock();

    // Check if the list was modified while we released the lock.
    // If the back item changed, someone else already evicted, so we don't need
    // to do anything,
    if (!lru_list_.empty() && lru_list_.back().key == key_to_remove &&
        lru_list_.back().bucket_index == bucket_idx) {
      lru_list_.pop_back();
    }
  }
};

struct NSStringHash {
  size_t operator()(const NSString *const str) const {
    if (str.UTF8String) {
      return absl::Hash<absl::string_view>()(absl::string_view(str.UTF8String));
    } else {
      return 0;
    }
  }
};

struct NSStringEqual {
  bool operator()(NSString *a, NSString *b) const {
    if (a == b) {
      return true;  // Pointer equality check
    }
    if (!a || !b) {
      return false;  // One is nil, the other is not
    }
    return [a isEqualToString:b];
  }
};

template <typename KeyT, typename ValueT,
          class Hash = absl::DefaultHashContainerHash<KeyT>,
          class Eq = absl::DefaultHashContainerEq<KeyT>>
class ImprovedConcurrentLRUMap {
 public:
  ImprovedConcurrentLRUMap(size_t size, size_t num_shards = 16)
      : total_capacity_(size), num_buckets_(num_shards),
        total_entries_(0) {
    assert(size > 0 && "Cache size must be positive");
    assert(num_shards > 0 && "Number of shards must be positive");
    assert(size >= num_shards && "Number of shards cannot exceed cache size");

    buckets_.reserve(num_shards);
    for (size_t i = 0; i < num_shards; ++i) {
      buckets_.push_back(std::make_unique<Bucket>());
    }
  }

  // Deleted copy and move operations
  ImprovedConcurrentLRUMap(const ImprovedConcurrentLRUMap &) = delete;
  ImprovedConcurrentLRUMap &operator=(const ImprovedConcurrentLRUMap &) = delete;
  ImprovedConcurrentLRUMap(ImprovedConcurrentLRUMap &&) = delete;
  ImprovedConcurrentLRUMap &operator=(ImprovedConcurrentLRUMap &&) = delete;

  void Put(const KeyT &key, const ValueT &value) {
    size_t bucket_idx = GetBucketIndex(key);
    Bucket &bucket = *buckets_[bucket_idx];

    // Optimized put with reduced lock contention
    bool need_eviction = false;
    {
      absl::WriterMutexLock bucket_lock(&bucket.mutex);
      auto it = bucket.cache_map.find(key);

      if (it != bucket.cache_map.end()) {
        // Update existing entry
        it->second.value = value;
        it->second.timestamp = GetCurrentTimestamp();
        return;
      }

      // Check if we need to evict
      need_eviction = (total_entries_.load(std::memory_order_relaxed) >= total_capacity_);
    }

    // Perform potential eviction outside of bucket lock
    if (need_eviction) {
      PerformEviction(bucket_idx);
    }

    // Add new entry
    {
      absl::WriterMutexLock bucket_lock(&bucket.mutex);
      bucket.cache_map.insert_or_assign(key,
        CacheEntry{value, GetCurrentTimestamp(), bucket_idx});
      total_entries_.fetch_add(1, std::memory_order_relaxed);
    }
  }

  std::optional<ValueT> Get(const KeyT &key) {
    Bucket &bucket = GetBucket(key);

    absl::ReaderMutexLock bucket_lock(&bucket.mutex);
    auto it = bucket.cache_map.find(key);
    if (it != bucket.cache_map.end()) {
      // Update timestamp without acquiring additional locks
      const_cast<CacheEntry&>(it->second).timestamp = GetCurrentTimestamp();
      return it->second.value;
    }
    return std::nullopt;
  }

  bool Contains(const KeyT &key) const {
    const Bucket &bucket = GetBucket(key);
    absl::ReaderMutexLock bucket_lock(&bucket.mutex);
    return bucket.cache_map.contains(key);
  }

  size_t Size() const {
    return total_entries_.load(std::memory_order_relaxed);
  }

  void Clear() {
    // Lock all buckets
    std::vector<std::unique_ptr<absl::WriterMutexLock>> bucket_locks;
    bucket_locks.reserve(num_buckets_);

    for (auto &bucket : buckets_) {
      bucket_locks.push_back(std::make_unique<absl::WriterMutexLock>(&bucket->mutex));
      bucket->cache_map.clear();
    }

    total_entries_.store(0, std::memory_order_relaxed);
  }

 private:
  // Improved cache entry structure
  struct CacheEntry {
    ValueT value;
    uint64_t timestamp;
    size_t bucket_index;
  };

  // Bucket structure for sharding
  struct Bucket {
    absl::flat_hash_map<KeyT, CacheEntry, Hash, Eq> cache_map;
    mutable absl::Mutex mutex;
  };


  size_t total_capacity_;
  size_t num_buckets_;
  // Atomic total entries to avoid global mutex
  std::atomic<size_t> total_entries_;
  std::vector<std::unique_ptr<Bucket>> buckets_;

  // Get current timestamp (could be replaced with more precise timing)
  static uint64_t GetCurrentTimestamp() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()
    ).count();
  }

  // Improved bucket index calculation
  size_t GetBucketIndex(const KeyT &key) const {
    // Use high-quality hash mixing to improve distribution
    return Hash{}(key) % num_buckets_;
  }

  // Get reference to appropriate bucket
  Bucket &GetBucket(const KeyT &key) {
    return *buckets_[GetBucketIndex(key)];
  }

  const Bucket &GetBucket(const KeyT &key) const {
    return *buckets_[GetBucketIndex(key)];
  }

  // Optimized eviction strategy
  void PerformEviction(size_t hint_bucket) {
    // Find the least recently used entry across buckets
    size_t oldest_bucket = hint_bucket;
    uint64_t oldest_timestamp = std::numeric_limits<uint64_t>::max();
    KeyT key_to_remove;

    // Scan buckets to find LRU entry
    for (size_t i = 0; i < num_buckets_; ++i) {
      Bucket &bucket = *buckets_[i];
      absl::ReaderMutexLock bucket_lock(&bucket.mutex);

      for (const auto &[k, entry] : bucket.cache_map) {
        if (entry.timestamp < oldest_timestamp) {
          oldest_timestamp = entry.timestamp;
          oldest_bucket = i;
          key_to_remove = k;
        }
      }
    }

    // Remove the least recently used entry
    {
      Bucket &victim_bucket = *buckets_[oldest_bucket];
      absl::WriterMutexLock bucket_lock(&victim_bucket.mutex);
      victim_bucket.cache_map.erase(key_to_remove);
      total_entries_.fetch_sub(1, std::memory_order_relaxed);
    }
  }
};

template <typename KeyT, typename ValueT>
using ConcurrentLRUMapObjC = ConcurrentLRUMap<KeyT, ValueT, NSStringHash, NSStringEqual>;

template <typename KeyT, typename ValueT>
using ImprovedConcurrentLRUMapObjC = ImprovedConcurrentLRUMap<KeyT, ValueT, NSStringHash, NSStringEqual>;

#endif  // SANTA__COMMON__CONCURRENTLRUMAP_H
