# frozen_string_literal: true
class Redis
  class Client
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
