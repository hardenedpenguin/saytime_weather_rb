# frozen_string_literal: true

require 'net/http'
require 'socket'
require 'uri'

module SaytimeWeather
  class HttpClient
    NOT_RETRYABLE = :not_retryable

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
        result = get_once(url, timeout, user_agent, max_redirects)
        return result if result.is_a?(String)
        break if result == NOT_RETRYABLE
        next if attempt == retries - 1

        sleep(retry_sleep)
      end
      nil
    end

    def close
      @connections.each_value do |http|
        http.finish if http.started?
      rescue IOError
        nil
      end
      @connections.clear
    end

    def get_once(url, timeout, user_agent, max_redirects)
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
            return get(redirect_uri.to_s, timeout, user_agent, max_redirects - 1)
          rescue => e
            w("Failed to follow redirect: #{e.message}")
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
        w('Rate limited by server, please wait before retrying')
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
