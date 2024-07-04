# frozen_string_literal: true

module GenericHelper
  def wait_for(timeout:, sleep_duration: 0.001, message: nil, &blk)
    till = (Time.now + timeout).to_i

    while Time.now.to_i < till && !blk.call
      sleep sleep_duration
      raise message || "Timeout after #{timeout} second" if Time.now.to_i >= till
    end
  end
end
