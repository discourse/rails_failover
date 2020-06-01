# frozen_string_literal: true

require "net/http"
require "uri"

module UrlHelper
  def get(path)
    uri = URI.parse(URI.join("http://localhost:8080", path).to_s)

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 5
    http.open_timeout = 5

    http.start do |h|
      h.get(uri.request_uri)
    end
  end

  def flood_get(path, times:)
    threads = []

    times.times do
      threads << Thread.new do
        yield get(path)
      end
    end

    threads.each(&:join)
  end
end
