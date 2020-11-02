# frozen_string_literal: true
class Redis
  module Connection
    class Ruby
      def disconnect
        @sock.shutdown
        @sock.close
      rescue
      ensure
        @sock = nil
      end
    end
  end
end
