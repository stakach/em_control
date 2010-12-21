

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
			@command_lock = Mutex.new
		end
		
		def post_init
			return unless self.respond_to?(:initiate_session)
			begin
				self.initiate_session
			rescue => e
				p e.message
				p e.backtrace
			end
		end
		
		def connection_completed
			if self.respond_to?(:connected)
				EM.defer do
					begin
						self.connected
					rescue => e
						p e.message
						p e.backtrace
					end
				end
			end
		end
		
		def unbind
			@selected.disconnected(self) unless @selected.nil?
		end
		
		def receive_data(data)
			@receive_queue.push(data)
			EM.defer do
				begin
					@command_lock.synchronize {
						self.received
					}
				rescue => e
					p e.message
					p e.backtrace
				end
			end
		end
	end
end