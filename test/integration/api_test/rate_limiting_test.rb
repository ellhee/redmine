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

require_relative '../../test_helper'

class Redmine::ApiTest::RateLimitingTest < Redmine::ApiTest::Base
  def setup
    super
    Setting.api_rate_limiting_enabled = '0'
    Redmine::RateLimit.reset_store!(max_size: 10_000)
  end

  def teardown
    Setting.api_rate_limiting_enabled = '0'
    Redmine::RateLimit.reset_store!(max_size: 10_000)
    super
  end

  # --- US5: Disabled by default ---

  def test_rate_limiting_disabled_by_default_returns_200
    Setting.api_rate_limiting_enabled = '0'
    5.times do
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :success
    end
  end

  def test_rate_limiting_disabled_no_ratelimit_headers
    Setting.api_rate_limiting_enabled = '0'
    get '/issues.json', :headers => credentials('jsmith', 'jsmith')
    assert_response :success
    assert_nil response.headers['X-RateLimit-Limit'],     "X-RateLimit-Limit should not be present when disabled"
    assert_nil response.headers['X-RateLimit-Remaining'], "X-RateLimit-Remaining should not be present when disabled"
    assert_nil response.headers['X-RateLimit-Reset'],     "X-RateLimit-Reset should not be present when disabled"
    assert_nil response.headers['Retry-After'],           "Retry-After should not be present when disabled"
  end

  # --- US4: Normal operation within limit ---

  def test_within_limit_returns_200_with_ratelimit_headers
    with_rate_limit_settings(max_requests: '10', period: '60') do
      3.times.each_with_index do |_, i|
        get '/issues.json', :headers => credentials('jsmith', 'jsmith')
        assert_response :success
        assert_equal '10', response.headers['X-RateLimit-Limit']
        assert_equal (10 - (i + 1)).to_s, response.headers['X-RateLimit-Remaining']
        assert response.headers['X-RateLimit-Reset'].to_i > 0, "X-RateLimit-Reset should be a positive timestamp"
      end
    end
  end

  def test_xml_format_also_has_ratelimit_headers
    with_rate_limit_settings(max_requests: '10', period: '60') do
      get '/issues.xml', :headers => credentials('jsmith', 'jsmith')
      assert_response :success
      assert_not_nil response.headers['X-RateLimit-Limit'],     "X-RateLimit-Limit should be present for XML"
      assert_not_nil response.headers['X-RateLimit-Remaining'], "X-RateLimit-Remaining should be present for XML"
      assert_not_nil response.headers['X-RateLimit-Reset'],     "X-RateLimit-Reset should be present for XML"
    end
  end

  # --- US1: Blocking ---

  def test_exceeding_limit_returns_429
    with_rate_limit_settings(max_requests: '3', period: '60') do
      3.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :too_many_requests
    end
  end

  def test_429_response_includes_retry_after_header
    with_rate_limit_settings(max_requests: '2', period: '60') do
      2.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :too_many_requests
      retry_after = response.headers['Retry-After'].to_i
      assert retry_after >= 1, "Retry-After should be a positive integer, got #{retry_after}"
    end
  end

  def test_429_body_is_neutral_does_not_reveal_token_validity
    with_rate_limit_settings(max_requests: '2', period: '60') do
      # Exhaust the limit for a specific IP (Rails test env uses 127.0.0.1)
      2.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }

      # Request with INVALID token while over limit
      get '/issues.json', :headers => credentials('invalid_token_xyz', 'X')
      assert_response :too_many_requests
      body_invalid_token = response.body

      # Reset store and exhaust limit again
      Redmine::RateLimit.reset_store!(max_size: 10_000)
      2.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }

      # Request with VALID token while over limit
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :too_many_requests
      body_valid_token = response.body

      # Bodies must be identical — rate limit does not reveal token validity (FR-011)
      assert_equal body_invalid_token, body_valid_token,
                   "429 body should be identical regardless of token validity"
    end
  end

  def test_valid_token_still_gets_429_when_limit_exceeded
    with_rate_limit_settings(max_requests: '3', period: '60') do
      3.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :too_many_requests, "Valid token should still get 429 when limit exceeded (US1 scenario 3)"
    end
  end

  def test_non_api_html_requests_are_not_rate_limited
    with_rate_limit_settings(max_requests: '1', period: '60') do
      5.times do
        get '/login'
        # HTML request — rate limiting should NOT apply (FR-008)
        assert_not_equal 429, response.status, "HTML requests should not be rate limited"
      end
    end
  end

  def test_rate_limit_resets_after_window_expires
    with_rate_limit_settings(max_requests: '3', period: '60') do
      3.times { get '/issues.json', :headers => credentials('jsmith', 'jsmith') }

      # Verify we are over the limit
      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :too_many_requests

      # Advance time past the window — capture now BEFORE stubbing
      now = Time.now
      Time.stubs(:now).returns(now + 61)

      get '/issues.json', :headers => credentials('jsmith', 'jsmith')
      assert_response :success, "Request should succeed after window expires"
    end
  end

  # --- FR-007: X-Forwarded-For ---

  def test_rate_limit_applies_to_real_ip_from_x_forwarded_for
    with_rate_limit_settings(max_requests: '2', period: '60') do
      forwarded_ip = '203.0.113.42'
      headers_with_xff = credentials('jsmith', 'jsmith').merge('X-Forwarded-For' => forwarded_ip)

      get '/issues.json', :headers => headers_with_xff
      assert_response :success
      assert_not_nil response.headers['X-RateLimit-Remaining'],
                     "X-RateLimit-Remaining should be present"

      get '/issues.json', :headers => headers_with_xff
      assert_response :success

      # Third request exceeds limit for this forwarded IP
      get '/issues.json', :headers => headers_with_xff
      assert_response :too_many_requests, "Requests from X-Forwarded-For IP should be rate limited"
    end
  end

  private

  def with_rate_limit_settings(max_requests: '300', period: '300', max_ips: '10000')
    Setting.api_rate_limiting_enabled   = '1'
    Setting.api_rate_limit_max_requests = max_requests
    Setting.api_rate_limit_period       = period
    Setting.api_rate_limit_max_ips      = max_ips
    yield
  ensure
    Setting.api_rate_limiting_enabled = '0'
  end
end
