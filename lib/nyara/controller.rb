module Nyara
  Controller = Struct.new :request, :response
  class Controller
    module KlassMethods
      def on method, path, &blk
        @actions ||= []
        @used_ids = {}
        @actions << [method, path, @curr_id, blk]
        if @curr_id
          raise ArgumentError, "action id #{@curr_id} already in use" if @used_ids[@curr_id]
          @used_ids[@curr_id] = true
          @curr_id = nil
        end
      end

      def tag tag
        # todo scan class
        id = tag[/\#\w++(\-\w++)*/]
        @curr_id = id
      end

      def get path, &blk
        on 'GET', path, &blk
      end

      def post path, &blk
        on 'POST', path, &blk
      end

      def put path, &blk
        on 'PUT', path, &blk
      end

      def delete path, &blk
        on 'DELETE', path, &blk
      end

      # [[method, path, id]]
      def preprocess_actions
        raise 'no action defined' unless @actions

        @curr_id = '#0'
        next_id = proc{
          while @used_ids[@curr_id]
            @curr_id = @curr_id.succ
          end
          @used_ids[@curr_id] = true
          @curr_id
        }
        next_id[]

        @actions.map do |action|
          method, path, id, blk = action
          unless id
            id = next_id[]
            action[2] = id
          end
          # todo path helper
          define_method id, &blk
          [method, path, id]
        end
      end
    end

    def self.inherited klass
      # klass will also have this inherited method
      klass.extend KlassMethods
    end

    def status n
      response.status = n
    end

    def send_data data
      response.send_data data
    end

    def render_header
      response.render_header
    end

    def render_string str
      str = str.to_s
      r = response
      r.header['Content-Length'] = str.bytesize
      r.render_header
      r.send_data str
      request.close_connection_after_writing
    end
  end
end
