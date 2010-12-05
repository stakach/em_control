
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
				@base.send(data, options)
				return @status[options[:wait_emit]]
			else
				@base.send(data, options)
			end
		end


		attr_reader :base
	end
end
