# frozen_string_literal: true

module Whoosh
  module Jobs
    class RedisBackend
      @redis_available = nil

      def self.available?
        if @redis_available.nil?
          @redis_available = begin
            require "redis"
            true
          rescue LoadError
            false
          end
        end
        @redis_available
      end

      def initialize(url:, prefix: "whoosh:jobs")
        unless self.class.available?
          raise Errors::DependencyError, "Jobs Redis backend requires the 'redis' gem"
        end
        @redis = Redis.new(url: url)
        @prefix = prefix
      end

      def push(job_data)
        serialized = Serialization::Json.encode(job_data)
        if job_data[:run_at] && job_data[:run_at] > Time.now.to_f
          # Scheduled: use sorted set with run_at as score
          @redis.zadd("#{@prefix}:scheduled", job_data[:run_at], serialized)
        else
          @redis.lpush("#{@prefix}:queue:#{job_data[:queue] || "default"}", serialized)
        end
      end

      def pop(timeout: 5, queues: ["default"])
        # First, promote scheduled jobs
        promote_scheduled

        # Try each queue in priority order
        queues.each do |queue|
          result = @redis.rpop("#{@prefix}:queue:#{queue}")
          if result
            return Serialization::Json.decode(result).transform_keys(&:to_sym)
          end
        end

        # Block-wait on default queue
        result = @redis.brpop("#{@prefix}:queue:#{queues.first}", timeout: timeout)
        if result
          Serialization::Json.decode(result[1]).transform_keys(&:to_sym)
        end
      rescue => e
        nil
      end

      def save(record)
        serialized = Serialization::Json.encode(record)
        @redis.set("#{@prefix}:record:#{record[:id]}", serialized, ex: 86400) # 24h TTL
      end

      def find(id)
        raw = @redis.get("#{@prefix}:record:#{id}")
        return nil unless raw
        data = Serialization::Json.decode(raw)
        data.transform_keys(&:to_sym)
      end

      def size
        pending_count + scheduled_count
      end

      def pending_count
        count = 0
        @redis.keys("#{@prefix}:queue:*").each do |key|
          count += @redis.llen(key)
        end
        count
      rescue => e
        0
      end

      def scheduled_count
        @redis.zcard("#{@prefix}:scheduled")
      rescue => e
        0
      end

      def shutdown
        @redis.close
      rescue => e
        # Already closed
      end

      private

      def promote_scheduled
        now = Time.now.to_f
        # Get all jobs ready to run
        ready = @redis.zrangebyscore("#{@prefix}:scheduled", "-inf", now.to_s)
        ready.each do |raw|
          # Remove from scheduled set
          removed = @redis.zrem("#{@prefix}:scheduled", raw)
          next unless removed

          job_data = Serialization::Json.decode(raw)
          queue = job_data["queue"] || "default"
          @redis.lpush("#{@prefix}:queue:#{queue}", raw)
        end
      rescue => e
        # Don't crash on promote errors
      end
    end
  end
end
