# frozen_string_literal: true

module GenericHelper
  def wait_for(timeout:, &blk)
    till = Time.now + (timeout.to_f / 1000)
    sleep 0.001 while Time.now < till && !blk.call
  end
end
