/// Copyright 2024 North Pole Security, Inc.
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

#ifndef SANTA__COMMON__RINGBUFFER_H
#define SANTA__COMMON__RINGBUFFER_H

#include <Foundation/Foundation.h>

#include <optional>
#include <vector>

namespace santa {

template <typename T>
class RingBuffer {
 public:
  RingBuffer(size_t capacity) : capacity_(capacity) {
    buffer_.reserve(capacity);
  }

  RingBuffer(RingBuffer&& other) = default;
  RingBuffer& operator=(RingBuffer&& rhs) = default;

  // Could be safe to implement these, but not currently needed
  RingBuffer(const RingBuffer& other) = delete;
  RingBuffer& operator=(const RingBuffer& other) = delete;

  bool Enqueue(const T& val) {
    bool dropped = false;
    if (Full()) {
      buffer_.erase(buffer_.begin());
      dropped = true;
    }
    buffer_.push_back(val);
    return dropped;
  }

  bool Enqueue(T&& val) {
    bool dropped = false;
    if (Full()) {
      buffer_.erase(buffer_.begin());
      dropped = true;
    }
    buffer_.push_back(std::move(val));
    return dropped;
  }

  std::optional<T> Dequeue() {
    if (Empty()) {
      return std::nullopt;
    } else {
      T value = std::move(buffer_.front());
      buffer_.erase(buffer_.begin());
      return std::make_optional<T>(value);
    }
  }

  inline size_t Capacity() const { return capacity_; }
  inline bool Empty() const { return buffer_.size() == 0; };
  inline bool Full() const { return buffer_.size() == capacity_; };

 private:
  size_t capacity_;
  std::vector<T> buffer_;
};

}  // namespace santa

#endif
