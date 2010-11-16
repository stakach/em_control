
module Control
	class Device
		def setbase(base)
			@base = base
			undef setbase	# Remove this function
		end

	
		def last_command	# use priority queues to allow for same syntax everywhere
			@base.last_command
		end


		def send(data, options = {})
			@base.send(data, options)
		end


		attr_reader :base
	end
end
