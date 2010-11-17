

module Control

	#
	# Base class for all control logic classes
	#
	class Logic
		include EventPublisher
		event :update_status
	
	end
end
