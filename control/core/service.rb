module Control

	class Service
		include ModuleCore
		
		def initialize
			@systems = []

			#
			# Status variables
			#	NOTE:: if changed then change in logic.rb 
			#
			@status = {}
			@status_lock = Mutex.new
			@system_lock = Mutex.new
			@status_waiting = false
		end
		
		protected
		
		def config
			ServiceModule.lookup(self)
		end
		
		def request(path, options = {}, *args, &block)
			error = true
			
			begin
				error = @base.do_send_request(path, options, *args, &block)
			rescue => e
				Control.print_error(logger, e, {
					:message => "module #{self.class} in request",
					:level => Logger::ERROR
				})
			ensure
				if error
					begin
						logger.warn "Request failed for: #{path.inspect}"
					rescue
						logger.error "Request failed, bad path data"
					end
				end
			end
			
		end
	end
	
end