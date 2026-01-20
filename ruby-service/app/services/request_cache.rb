require 'digest'

class RequestCache
  def initialize(max_entries: 500)
    @cache = {}
    @max_entries = max_entries
  end

  def get(request_data)
    key = cache_key(request_data)
    entry = @cache[key]

    return nil unless entry

    if entry[:expires_at] && Time.now > entry[:expires_at]
      @cache.delete(key)
      return nil
    end

    entry[:data]
  end

  def set(request_data, response_data, ttl: 300)
    evict_if_needed

    key = cache_key(request_data)
    @cache[key] = {
      data: response_data,
      expires_at: ttl ? Time.now + ttl : nil,
      created_at: Time.now
    }
  end

  def invalidate(request_data)
    key = cache_key(request_data)
    @cache.delete(key)
  end

  def clear
    @cache.clear
  end

  def size
    @cache.size
  end

  private

  def cache_key(data)
    content = data.is_a?(Hash) ? data.sort.to_h.to_json : data.to_s
    Digest::SHA256.hexdigest(content)
  end

  def evict_if_needed
    return unless @cache.size >= @max_entries

    oldest_key = @cache.min_by { |k, v| v[:created_at] }&.first
    @cache.delete(oldest_key) if oldest_key
  end
end
