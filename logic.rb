

module Control

	#
	# Base class for all control logic classes
	#
	class Logic
		include Status
		include Constants
		

		def task callback = nil, &block
			if callback.nil?
				EM.defer(block)
			else
				EM.defer(block, callback)
			end
		end
		
	end
end
