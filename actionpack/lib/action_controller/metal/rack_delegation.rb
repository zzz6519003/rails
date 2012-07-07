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
          @response.headers['Cache-Control'] = 'no-cache'
          @response.headers.delete 'Content-Length'
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

      attr_reader :stream

      def initialize(status = 200, header = {}, body = [])
        @stream = Buffer.new self
        super(status, header, stream)
      end
    end

    def dispatch(action, request)
      set_response!(request)
      super(action, request)
    end

    def process(name)
      t1 = Thread.current
      locals = t1.keys.map { |key| [key, t1[key]] }

      Thread.new {
        t2 = Thread.current
        t2.abort_on_exception = true
        locals.each { |k,v| t2[k] = v }

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
      @_response         = AsyncResponse.new
      @_response.request = request
    end
  end
end
