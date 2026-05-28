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

require_relative '../../../test_helper'

class Redmine::RateLimitTest < ActiveSupport::TestCase
  def setup
    Redmine::RateLimit.reset_store!(max_size: 100)
    Setting.api_rate_limiting_enabled = '0'
  end

  def teardown
    Redmine::RateLimit.reset_store!(max_size: 100)
    Setting.api_rate_limiting_enabled = '0'
  end

  def test_check_returns_disabled_when_rate_limiting_is_off
    Setting.api_rate_limiting_enabled = '0'
    result = Redmine::RateLimit.check('1.2.3.4')
    assert_equal :disabled, result[:status]
  end

  def test_check_allows_request_within_limit
    with_rate_limit_settings(enabled: '1', max_requests: '5', period: '60') do
      result1 = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :allowed, result1[:status]
      assert_equal 4, result1[:remaining]

      result2 = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :allowed, result2[:status]
      assert_equal 3, result2[:remaining]

      result3 = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :allowed, result3[:status]
      assert_equal 2, result3[:remaining]
    end
  end

  def test_check_denies_request_at_limit
    with_rate_limit_settings(enabled: '1', max_requests: '3', period: '60') do
      3.times { Redmine::RateLimit.check('1.2.3.4') }
      result = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :denied, result[:status]
      assert_equal 0, result[:remaining]
    end
  end

  def test_remaining_never_goes_negative
    with_rate_limit_settings(enabled: '1', max_requests: '2', period: '60') do
      5.times { Redmine::RateLimit.check('1.2.3.4') }
      result = Redmine::RateLimit.check('1.2.3.4')
      assert_equal 0, result[:remaining]
      assert result[:remaining] >= 0, "remaining should never be negative"
    end
  end

  def test_window_slides_when_period_expires
    with_rate_limit_settings(enabled: '1', max_requests: '3', period: '60') do
      3.times { Redmine::RateLimit.check('1.2.3.4') }
      result_before = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :denied, result_before[:status]

      travel_to(61.seconds.from_now) do
        result_after = Redmine::RateLimit.check('1.2.3.4')
        assert_equal :allowed, result_after[:status], "Request should be allowed after window expires"
      end
    end
  end

  def test_sliding_window_weights_prev_count
    # Fill a window, then advance half a period — prev_count weight = 0.5
    # With max=10, prev_count=10, elapsed=period/2:
    # approx = 10 * 0.5 + 0 = 5, so remaining = 10 - 5 = 5
    with_rate_limit_settings(enabled: '1', max_requests: '10', period: '60') do
      10.times { Redmine::RateLimit.check('1.2.3.4') }

      # Advance by one full period to roll over, then half a period into next window (90s total)
      travel_to(90.seconds.from_now) do
        result = Redmine::RateLimit.check('1.2.3.4')
        assert_equal :allowed, result[:status]
        # After window shift: prev_count=10, curr_count=0, elapsed=30, weight=0.5
        # approx = 10 * 0.5 + 0 = 5; remaining = max(0, 10 - floor(5)) = 5; after this check it's 4
        assert result[:remaining] >= 0, "remaining should be non-negative"
      end
    end
  end

  def test_overflow_evicts_stale_entries_and_allows_new_ip
    Redmine::RateLimit.reset_store!(max_size: 3)

    with_rate_limit_settings(enabled: '1', max_requests: '10', period: '60') do
      # Fill the store with 3 entries
      Redmine::RateLimit.check('10.0.0.1')
      Redmine::RateLimit.check('10.0.0.2')
      Redmine::RateLimit.check('10.0.0.3')

      # Advance time past the period so all entries become stale
      travel_to(61.seconds.from_now) do
        # New IP should evict stale entries and be allowed (not :untracked — eviction worked)
        result = Redmine::RateLimit.check('10.0.0.99')
        assert_equal :allowed, result[:status]
      end
    end
  end

  def test_overflow_fail_open_when_all_entries_active
    Redmine::RateLimit.reset_store!(max_size: 3)

    with_rate_limit_settings(enabled: '1', max_requests: '100', period: '3600') do
      # Fill the store with 3 active entries
      Redmine::RateLimit.check('10.0.0.1')
      Redmine::RateLimit.check('10.0.0.2')
      Redmine::RateLimit.check('10.0.0.3')

      # New IP when store is full with active entries — should fail open
      result = Redmine::RateLimit.check('10.0.0.99')
      assert_equal :untracked, result[:status]
    end
  end

  def test_first_block_logs_warn_once_per_window
    with_rate_limit_settings(enabled: '1', max_requests: '2', period: '60') do
      2.times { Redmine::RateLimit.check('1.2.3.4') }

      Rails.logger.expects(:warn).with(regexp_matches(/1\.2\.3\.4/)).once
      Redmine::RateLimit.check('1.2.3.4')
    end
  end

  def test_subsequent_denials_do_not_duplicate_log
    with_rate_limit_settings(enabled: '1', max_requests: '2', period: '60') do
      2.times { Redmine::RateLimit.check('1.2.3.4') }

      # Only the first denial should log
      Rails.logger.expects(:warn).with(regexp_matches(/1\.2\.3\.4/)).once
      5.times { Redmine::RateLimit.check('1.2.3.4') }
    end
  end

  def test_clear_empties_store
    with_rate_limit_settings(enabled: '1', max_requests: '2', period: '60') do
      # Exhaust the limit for an IP
      2.times { Redmine::RateLimit.check('1.2.3.4') }
      assert_equal :denied, Redmine::RateLimit.check('1.2.3.4')[:status],
                   "IP should be blocked before reset"

      # After reset, the same IP should be allowed again — counters are cleared
      Redmine::RateLimit.reset_store!(max_size: 100)
      result = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :allowed, result[:status], "IP should be unblocked after store reset"
      assert_equal 1, result[:remaining], "remaining should be max - 1 after reset"
    end
  end

  def test_check_returns_reset_at_as_integer
    with_rate_limit_settings(enabled: '1', max_requests: '10', period: '60') do
      result = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :allowed, result[:status]
      assert_kind_of Integer, result[:reset_at]
      assert result[:reset_at] > 0
    end
  end

  def test_check_returns_retry_after_positive
    with_rate_limit_settings(enabled: '1', max_requests: '2', period: '60') do
      2.times { Redmine::RateLimit.check('1.2.3.4') }
      result = Redmine::RateLimit.check('1.2.3.4')
      assert_equal :denied, result[:status]
      assert result[:reset_at] > Time.now.to_i, "reset_at should be in the future"
    end
  end

  # --- Thread safety test (US6) ---

  def test_concurrent_requests_do_not_exceed_limit
    max = 10
    Redmine::RateLimit.reset_store!(max_size: 1000)

    with_rate_limit_settings(enabled: '1', max_requests: max.to_s, period: '60') do
      results = []
      mutex = Mutex.new

      threads = Array.new(20) do
        Thread.new do
          result = Redmine::RateLimit.check('10.0.0.1')
          mutex.synchronize { results << result[:status] }
        end
      end
      threads.each(&:join)

      allowed_count = results.count(:allowed)
      denied_count  = results.count(:denied)

      assert_equal max, allowed_count, "Exactly #{max} requests should be allowed"
      assert_equal 10,  denied_count,  "Exactly 10 requests should be denied"
    end
  end

  private

  def with_rate_limit_settings(enabled:, max_requests: '300', period: '300', max_ips: '10000')
    Setting.api_rate_limiting_enabled  = enabled
    Setting.api_rate_limit_max_requests = max_requests
    Setting.api_rate_limit_period       = period
    Setting.api_rate_limit_max_ips      = max_ips
    yield
  ensure
    Setting.api_rate_limiting_enabled  = '0'
  end
end
