# frozen_string_literal: true

require 'net/http'
require 'socket'
require 'uri'

module SaytimeWeather
  class HttpClient
    attr_accessor :verbose

    def initialize(warn_proc: nil, verbose: false)
      @warn_proc = warn_proc
      @verbose = verbose
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
        return result if result
        next if attempt == retries - 1

        sleep(retry_sleep)
      end
      nil
    end

    def get_once(url, timeout, user_agent, max_redirects)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = user_agent || SaytimeWeather::Endpoints::DEFAULT_HTTP_UA

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
      when 429
        w('Rate limited by server, please wait before retrying')
        nil
      when 404
        nil
      else
        w("HTTP error #{response_code} from #{uri.host}")
        nil
      end
    rescue URI::InvalidURIError
      w("Invalid URL: #{url}")
      nil
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

    def w(msg)
      return unless @verbose && @warn_proc

      @warn_proc.call(msg)
    end
  end
end
