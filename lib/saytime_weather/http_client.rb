# frozen_string_literal: true

require 'net/http'
require 'socket'
require 'time'
require 'uri'

module SaytimeWeather
  class HttpClient
    NOT_RETRYABLE = :not_retryable
    # Upper bound for honoring a server Retry-After header (announcements are time-sensitive).
    MAX_RETRY_AFTER = 10

    attr_accessor :verbose

    def initialize(warn_proc: nil, verbose: false)
      @warn_proc = warn_proc
      @verbose = verbose
      @connections = {}
    end

    def retries
      SaytimeWeather::Network.retries
    end

    def retry_sleep
      SaytimeWeather::Network.retry_sleep
    end

    def get(url, timeout = SaytimeWeather::Network.timeout_short, user_agent = nil, max_redirects = 5)
      return nil if max_redirects <= 0

      retries.times do |attempt|
        @retry_after = nil
        result = get_once(url, timeout, user_agent, max_redirects)
        return result if result.is_a?(String)
        break if result == NOT_RETRYABLE
        next if attempt == retries - 1

        sleep(retry_delay)
      end
      nil
    end

    def retry_delay
      return retry_sleep unless @retry_after

      [[@retry_after, retry_sleep].max, MAX_RETRY_AFTER].min
    end

    def close
      @connections.each_value do |http|
        http.finish if http.started?
      rescue IOError
        nil
      end
      @connections.clear
    end

    # Single attempt (redirects are followed here, without starting a new retry loop).
    def get_once(url, timeout, user_agent, max_redirects)
      if max_redirects <= 0
        w("Too many redirects for #{url}")
        return NOT_RETRYABLE
      end

      uri = URI(url)
      http = connection_for(uri, timeout)

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = user_agent || SaytimeWeather::Endpoints::DEFAULT_HTTP_UA
      request['Connection'] = 'keep-alive'

      response = http.request(request)
      response_code = response.code.to_i

      case response_code
      when 200
        response.body
      when 301, 302, 303, 307, 308
        location = response['Location'] || response['location']
        if location
          begin
            redirect_uri = URI(location)
            redirect_uri = uri + redirect_uri if redirect_uri.relative?
            if uri.scheme == 'https' && redirect_uri.scheme != 'https'
              w("Refusing insecure redirect from #{uri.host} to #{redirect_uri}")
              return NOT_RETRYABLE
            end
            return get_once(redirect_uri.to_s, timeout, user_agent, max_redirects - 1)
          rescue URI::InvalidURIError => e
            w("Failed to follow redirect: #{e.message}")
            return NOT_RETRYABLE
          end
        end
        nil
      when 404
        NOT_RETRYABLE
      when 401
        if uri.host&.include?('weatherapi.com')
          w('WeatherAPI authentication failed (check weatherapi_key or WEATHERAPI_KEY)')
        else
          w("HTTP error 401 from #{uri.host}")
        end
        NOT_RETRYABLE
      when 403
        if uri.host&.include?('weatherapi.com')
          w('WeatherAPI access denied (check API key and account quota)')
        else
          w("HTTP error 403 from #{uri.host}")
        end
        NOT_RETRYABLE
      when 429
        @retry_after = parse_retry_after(response['Retry-After'])
        w("Rate limited by #{uri.host}#{@retry_after ? " (Retry-After #{@retry_after}s)" : ''}")
        nil
      else
        w("HTTP error #{response_code} from #{uri.host}")
        nil
      end
    rescue URI::InvalidURIError
      w("Invalid URL: #{url}")
      NOT_RETRYABLE
    rescue Net::OpenTimeout, Net::ReadTimeout
      w("Request timeout for #{url}")
      nil
    rescue SocketError => e
      w("DNS/network error for #{uri.host}: #{e.message}")
      nil
    rescue => e
      w("HTTP request failed: #{e.message}")
      nil
    end

    private

    # Retry-After is either delta-seconds or an HTTP date.
    def parse_retry_after(value)
      v = value.to_s.strip
      return nil if v.empty?
      return v.to_i if v.match?(/\A\d+\z/)

      secs = (Time.httpdate(v) - Time.now).ceil
      secs.positive? ? secs : 0
    rescue ArgumentError
      nil
    end

    def connection_for(uri, timeout)
      key = "#{uri.scheme}://#{uri.host}:#{uri.port}"
      http = @connections[key]
      if http.nil? || !http.started?
        http&.finish rescue nil
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.keep_alive_timeout = 30
        http.start
        @connections[key] = http
      end
      http.open_timeout = timeout
      http.read_timeout = timeout
      http
    end

    def w(msg)
      $stderr.puts "WARNING: #{msg}"
      @warn_proc.call(msg) if @verbose && @warn_proc
    end
  end
end
