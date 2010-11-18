
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
			@base.send(data, options)
		end


		attr_reader :base
	end
end
