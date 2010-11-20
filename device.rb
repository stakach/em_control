
module Control
	class Device
		include Status	# The observable pattern (Should not be called directly)
		include Constants

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


		def send(data, options = {})
			if !options[:wait_emit].nil?
				
				#
				# Safety timer for wait
				#	(prevent system coming to a standstill)
				#		5 second default
				#
				timeout = options[:timeout] || 5
				EM.add_timer timeout, proc { 
					@status_lock.synchronize {
						if !@wait_status.nil?
							@wait_condition.signal		# wake up the thread
							#
							# TODO:: log the event here
							#	EM.defer(proc {log_issue})	# lets not waste time in this thread
							#
						end
					}
				}

				@status_lock.synchronize {				# defined in status module
					@wait_status = options[:wait_emit]
					
					@base.send(data, options)
					@wait_condition.wait(@status_lock)	# wait until the signal has been recieved
					
					@wait_status = nil					# this will run after the status has been recieved
				}
				return self[options[:wait_emit]]		# return the status value
			else
				@base.send(data, options)
			end
		end


		attr_reader :base
	end
end
