

module Control

	#
	# Base class for all control logic classes
	#
	class Logic
		include Status
		include Constants
		
		def initialize(system)
			@system = system
		end
		
		protected
		
		attr_reader :system
		
		def register(mod, status, &block)
			@system.communicator.register(self, mod, status, &block) 
		end
		
		def unregister(mod, status, &block)
			@system.communicator.unregister(self, mod, status, &block) 
		end

		def task callback = nil, &block
			if callback.nil?
				EM.defer &block					# Higher performance using blocks?
			else
				EM.defer(nil, callback, &block)
			end
		end
	end
end
