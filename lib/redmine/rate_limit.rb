# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module Redmine
  module RateLimit
    # Internal: two-counter sliding window approximation store.
    # Thread-safe via a single Mutex.
    class Store
      IPRecord = Struct.new(:prev_count, :curr_count, :window_start, :logged_this_window)

      def initialize(max_size)
        @max_size = max_size
        @data     = {}
        @mutex    = Mutex.new
      end

      # Checks and records a request for the given IP.
      #
      # Returns a Hash:
      #   { status: :allowed,   remaining: Integer, reset_at: Integer }
      #   { status: :denied,    remaining: 0,        reset_at: Integer }
      #   { status: :untracked, remaining: max,       reset_at: Integer }  # store full
      def check_and_record(ip, max_requests, period)
        @mutex.synchronize do
          now = Time.now.to_f

          record = @data[ip]

          if record.nil?
            # New IP — check capacity
            if @data.size >= @max_size
              evict_stale!(now, period)
              if @data.size >= @max_size
                Rails.logger.warn(
                  "[RateLimit] Store at capacity (#{@max_size} entries), " \
                  "skipping tracking for #{ip}"
                )
                reset_at = (now + period).ceil
                return {status: :untracked, remaining: max_requests, reset_at: reset_at}
              end
            end
            record = IPRecord.new(0, 0, now, false)
            @data[ip] = record
          end

          # Slide the window if the current window has expired
          elapsed = now - record.window_start
          if elapsed >= period
            record.prev_count  = record.curr_count
            record.curr_count  = 0
            record.window_start += period
            record.logged_this_window = false
            elapsed = now - record.window_start
            # Handle multiple expired periods (very long gaps)
            if elapsed >= period
              record.prev_count  = 0
              record.curr_count  = 0
              record.window_start = now
              elapsed = 0.0
            end
          end

          weight_prev  = (period - elapsed) / period.to_f
          approx_count = record.prev_count * weight_prev + record.curr_count
          reset_at     = (record.window_start + period).ceil

          if approx_count >= max_requests
            # Log the first block in this window only
            unless record.logged_this_window
              record.logged_this_window = true
              Rails.logger.warn(
                "[RateLimit] Blocked IP #{ip}: #{approx_count.ceil} requests " \
                "in #{period}s window at #{Time.now}"
              )
            end
            return {status: :denied, remaining: 0, reset_at: reset_at}
          end

          record.curr_count += 1
          remaining = [max_requests - (approx_count + 1).floor, 0].max
          {status: :allowed, remaining: remaining, reset_at: reset_at}
        end
      end

      def size
        @mutex.synchronize { @data.size }
      end

      private

      # Evicts entries whose approximated count is effectively zero (no traffic
      # in the last two windows). Called when the store is at capacity.
      def evict_stale!(now, period)
        @data.delete_if do |_ip, record|
          elapsed = now - record.window_start
          if elapsed >= period
            # Window rolled over — prev_count is old, curr is zero (no new traffic)
            weight_prev  = [0.0, (period - (elapsed - period)) / period.to_f].max
            approx_count = record.prev_count * weight_prev
          else
            weight_prev  = (period - elapsed) / period.to_f
            approx_count = record.prev_count * weight_prev + record.curr_count
          end
          approx_count < 1.0
        end
      end
    end

    # Module-level state: a single Store instance, replaced on reset.
    @store    = Store.new(10_000)
    @store_mutex = Mutex.new

    class << self
      # Public interface -------------------------------------------------------

      # Checks whether the given IP is within the rate limit.
      #
      # Returns:
      #   { status: :disabled }                                       — rate limiting off
      #   { status: :allowed,   remaining: Integer, reset_at: Integer }
      #   { status: :denied,    remaining: 0,        reset_at: Integer }
      #   { status: :untracked, remaining: Integer,  reset_at: Integer } — store overflow
      def check(ip)
        return {status: :disabled} unless enabled?

        max_requests = Setting.api_rate_limit_max_requests.to_i
        period       = Setting.api_rate_limit_period.to_i

        store.check_and_record(ip, max_requests, period)
      end

      # Replaces the store with a fresh empty instance.
      # Call this whenever rate-limit settings change.
      # max_size is coerced to Integer to guard against String values from Setting[].
      def reset_store!(max_size: 10_000)
        @store_mutex.synchronize do
          @store = Store.new(max_size.to_i)
        end
      end

      # Returns true when rate limiting is active per admin settings.
      def enabled?
        Setting.api_rate_limiting_enabled?
      end

      private

      def store
        @store_mutex.synchronize { @store }
      end
    end
  end
end
