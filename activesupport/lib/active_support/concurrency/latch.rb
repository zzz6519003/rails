require 'thread'

module ActiveSupport
  module Concurrency
    class Latch
      def initialize(count = 1)
        @count = count
        @mutex = Mutex.new
        @cond = ConditionVariable.new
      end

      def release
        @mutex.synchronize {
          @count -= 1 if @count > 0
          @cond.broadcast if @count.zero?
        }
      end

      def await
        @mutex.synchronize {
          @cond.wait @mutex if @count > 0
        }
      end
    end
  end
end
