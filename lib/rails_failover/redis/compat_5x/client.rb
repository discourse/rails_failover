# frozen_string_literal: true

module RailsFailover
  class Redis
    class Client < ::Redis::Client
      def initialize(config, **kwargs)
        super
        @config = RailsFailover::Redis::Config.new(config)
      end

      def connect
        Handler.instance.register_client(self, id)
        super
      end

      def on_disconnect
        Handler.instance.deregister_client(self, id)
      end
    end
  end
end
