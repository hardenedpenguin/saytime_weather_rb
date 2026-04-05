# frozen_string_literal: true

module SaytimeWeather
  module Network
    class << self
      attr_accessor :timeout_short, :timeout_long, :nominatim_delay,
                    :retries, :retry_sleep, :airports_cache_max_age, :airports_data_url

      def reset_defaults!
        @timeout_short = 10
        @timeout_long = 15
        @nominatim_delay = 1
        @retries = 3
        @retry_sleep = 1
        @airports_cache_max_age = 7 * 24 * 3600
        @airports_data_url = 'https://ourairports.com/data/airports.csv'
      end
    end

    reset_defaults!
  end
end
