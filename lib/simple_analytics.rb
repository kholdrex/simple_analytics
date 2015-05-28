require 'simple_analytics/version'
require 'json'
require 'google/api_client'

module SimpleAnalytics
  # Required query parameters are used to configure which data to return from Google Analytics.
  REQUIRED_PROPERTIES = ['ids', 'start-date', 'end-date', 'metrics']
  API_URL = 'https://www.googleapis.com/analytics/v3/data/ga'

  class NotSuccessfulResponseError < RuntimeError; end

  class Api
    attr_accessor :auth_token

    # +rows+ is a 2-dimensional array of strings, each string represents a value in the table.
    # +body+ is the data in response body.
    attr_reader :rows, :body

    def self.authenticate(username, key_path, options = {})
      analytics = new(username, key_path, options)
      analytics.authenticate
      analytics
    end

    def initialize(username, key_path, options = {})
      @username = username
      @key_path = key_path
      @options  = options
    end

    def authenticate
      client = Google::APIClient.new
      client.authorization = Signet::OAuth2::Client.new(
          :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
          :audience => 'https://accounts.google.com/o/oauth2/token',
          :scope => 'https://www.googleapis.com/auth/analytics.readonly',
          :issuer => @username,
          :signing_key => key)

      ## Request a token for our service account
      client.authorization.fetch_access_token!
      @auth_token = client.authorization.access_token
    end

    def fetch(properties)
      check_properties(properties)

      uri = URI.parse(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      headers = { 'GData-Version' => '3' }
      response = http.get("#{uri.path}?#{query_string(properties)}&access_token=#{@auth_token}", headers)
      raise NotSuccessfulResponseError.new, response.body if response.code_type != Net::HTTPOK
      @body = JSON.parse(response.body)
      @rows = @body['rows']
    end

    private

    def key
      Google::APIClient::KeyUtils.load_from_pkcs12(@key_path, 'notasecret')
    end

    def check_properties(properties)
      required = properties.keys.map(&:to_s) & REQUIRED_PROPERTIES
      if required.size != REQUIRED_PROPERTIES.size
        raise ArgumentError, "Properties: #{REQUIRED_PROPERTIES.join(', ')} are required."
      end
    end

    def query_string(properties)
      properties.map { |k, v| "#{k}=#{escape v}" }.sort.join('&')
    end

    def escape(property)
      URI.escape(property.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    end
  end
end
