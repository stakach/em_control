

#
# This reduces load on the reactor thread.
#	Use as a helper if desired
#
module Control
	class Deferred < EventMachine::Connection
		def initialize(*args)
			super

			@selected = nil
			@receive_queue = Queue.new
		end
		
		def post_init
			self.initiate_session if self.respond_to?(:initiate_session)
		end
		
		def connection_completed
			if self.respond_to?(:connected)
				operation = proc { self.connected }
				EM.defer(operation)
			end
		end
		
		def unbind
			@selected.disconnected(self) unless @selected.nil?
		end
		
		def receive_data(data)
			@receive_queue.push(data)
			operation = proc { self.received }
			EM.defer(operation)
		end
	end
end