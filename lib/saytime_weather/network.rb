# frozen_string_literal: true

module SaytimeWeather
  module Network
    class << self
      attr_accessor :timeout_short, :timeout_long, :probe_timeout, :nominatim_delay,
                    :retries, :retry_sleep, :airports_cache_max_age, :airports_data_url,
                    :geocode_cache_max_age, :timezone_cache_max_age, :random_max_attempts

      def reset_defaults!
        @timeout_short = 10
        @timeout_long = 15
        @probe_timeout = 5
        @nominatim_delay = 1
        @retries = 3
        @retry_sleep = 1
        @airports_cache_max_age = 7 * 24 * 3600
        @airports_data_url = 'https://ourairports.com/data/airports.csv'
        @geocode_cache_max_age = 30 * 24 * 3600
        @timezone_cache_max_age = 7 * 24 * 3600
        @random_max_attempts = 3
      end
    end

    reset_defaults!
  end
end
