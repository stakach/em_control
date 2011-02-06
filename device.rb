
module Control
	class Device
		include Status	# The observable pattern (Should not be called directly)
		include Constants
		include Utilities
		
		def initialize(system)
			@system = system		

			#
			# Status variables
			#	NOTE:: if changed then change in logic.rb 
			#
			@status = {}
			@status_lock = Mutex.new
			@status_emit = {}	# status => condition_variable
		end

		#
		# Sets up a link for the user code to the eventmachine class
		#	This way the namespace is clean.
		#
		def setbase(base)
			@base = base
			undef setbase	# Remove this function
		end

	
		def last_command	# get the last command sent that was (this is very contextual)
			@base.last_command
		end
		

		def logger
			@system.logger
		end
		

		protected
		

		attr_reader :system
		attr_reader :base


		def send(data, options = {})
			inline = @base.send(data, options)
			if !options[:emit].nil? && self[:connected]
				@status_lock.synchronize {
					return @status[options[:emit]] if inline == true
				
					#
					# The command is queued - we need to wait for the status to be emited
					#
					if @status_emit[options[:emit]].nil?
						@status_emit[options[:emit]] = ConditionVariable.new
					end
					
					@timeout = EM::Timer.new(15) do 
						@status_lock.synchronize {
							if @status_emit.has_key?(options[:emit])
								var = @status_emit.delete(options[:emit])
								var.broadcast		# wake up the thread
								
								@timeout = nil
								
								#
								# log the event here
								#
								EM.defer do
									@logger.debug "-- module #{self.class} in device.rb, send --"
									@logger.debug "An emit timeout occured"
								end
							end
						}
					end	

					@status_emit[options[:emit]].wait(@status_lock)
					
					return @status[options[:emit]]
				}
			end
		end
	end
end
