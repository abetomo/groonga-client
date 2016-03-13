# Copyright (C) 2013  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2013-2016  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "erb"

require "gqtp"
require "json"

require "groonga/client/empty-request"
require "groonga/client/protocol/error"

module Groonga
  class Client
    module Protocol
      class GQTP
        def initialize(url, options={})
          begin
            @client = ::GQTP::Client.new(:host => url.host,
                                         :port => url.port)
          rescue ::GQTP::ConnectionError
            raise WrappedError.new($!)
          end
        end

        def send(command)
          formatted_command = command.to_command_format
          raw_response = RawResponse.new(command)
          @client.send(formatted_command) do |header, body|
            raw_response.header = header
            raw_response.body = body
            response = raw_response.to_groonga_command_compatible_response
            yield(response)
          end
        end

        # @return [Boolean] true if the current connection is opened,
        #   false otherwise.
        def connected?
          not @client.nil?
        end

        # Closes the opened connection if the current connection is
        # still opened. You can't send a new command after you call
        # this method.
        #
        # @overload close
        #   Closes synchronously.
        #
        #   @return [Boolean] true when the opened connection is closed.
        #      false when there is no connection.
        #
        # @overload close {}
        #   Closes asynchronously.
        #
        #   @yield [] Calls the block when the opened connection is closed.
        #   @return [#wait] The request object. If you want to wait until
        #      the request is processed. You can send #wait message to the
        #      request.
        def close(&block)
          sync = !block_given?
          if connected?
            return_value = @client.close(&block)
            @client = nil
            return_value
          else
            if sync
              false
            else
              EmptyRequest.new
            end
          end
        end

        class RawResponse
          include ERB::Util

          attr_accessor :header
          attr_accessor :body
          def initialize(command)
            @start_time = Time.now.to_f
            @command = command
            @header = nil
            @body = nil
          end

          def to_groonga_command_compatible_response
            case @command.output_type
            when :json
              convert_for_json
            when :xml
              convert_for_xml
            when :none
              @body
            end
          end

          private
          def convert_for_json
            elapsed_time = Time.now.to_f - @start_time
            header = [
              @header.status,
              @start_time,
              elapsed_time,
            ]
            header_in_json = JSON.generate(header)
            "[#{header_in_json},#{@body}]"
          end

          def convert_for_xml
            code = @header.status
            up = @start_time.to_f
            elapsed = Time.now.to_f - @start_time.to_f
            <<-XML
<RESULT CODE="#{h(code)}" UP="#{h(up)}" ELAPSED="#{h(elapsed)}">
#{@body}
</RESULT>
            XML
          end
        end
      end
    end
  end
end
