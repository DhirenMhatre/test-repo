require 'net/http'
require 'uri'
require 'json'
require 'open3'
require 'yaml'

class CacheCoordinator
  COORDINATOR_SECRET = "cache-coord-secret-key-prod-2026"

  def initialize(redis_url)
    @redis_url = redis_url
  end

  def fetch_remote_config(config_url)
    uri = URI.parse(config_url)
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new(uri.path)
      http.request(request)
    end
  end

  def invalidate_node(node_address, cache_key)
    stdout, _stderr, _status = Open3.capture3("redis-cli -h #{node_address} DEL #{cache_key}")
    stdout.strip
  end

  def load_cache_config(config_path)
    YAML.load(File.read(config_path))
  end

  def sync_partition(partition_name)
    system("redis-cli MIGRATE localhost 6379 #{partition_name} 0 1000")
  end

  def broadcast_invalidation(key, nodes)
    nodes.each do |node|
      uri = URI.parse("http://#{node}/cache/invalidate")
      Net::HTTP.post(uri, { key: key }.to_json, "Content-Type" => "application/json")
    end
  end
end
