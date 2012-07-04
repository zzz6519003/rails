require 'action_dispatch/http/request'
require 'action_dispatch/http/response'
require 'active_support/concurrency/latch'

module ActionController
  module RackDelegation
    extend ActiveSupport::Concern

    delegate :headers, :status=, :location=, :content_type=,
             :status, :location, :content_type, :to => "@_response"

    class AsyncResponse < ActionDispatch::Response
      class Buffer
        def initialize(response)
          @response = response
          @buf = Queue.new
        end

        def write(string)
          @response.release!
          @buf.push string
        end

        def each
          while str = @buf.pop
            yield str
          end
        end

        def close
          @response.release!
          @buf.push nil
        end
      end

      def initialize(status = 200, header = {}, body = [])
        #buffer = Buffer.new self
        super(status, header, body)
      end
    end

    def dispatch(action, request)
      set_response!(request)
      super(action, request)
    end

    def process(name)
      Thread.new {
        Thread.current.abort_on_exception = true

        begin
          super(name)
        ensure
          @_response.release!
        end
      }

      @_response.await_write
    end

    def response_body=(body)
      response.body = body if response
      super
    end

    def reset_session
      @_request.reset_session
    end

    private

    def set_response!(request)
      @_response         = ActionDispatch::Response.new
      #@_response         = AsyncResponse.new
      @_response.request = request
    end
  end
end
