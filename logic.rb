

module Control

	#
	# Base class for all control logic classes
	#
	class Logic
		include Status
		include Constants
		
		def initialize(system)
			@system = system
			
			#
			# Status variables
			#	NOTE:: if changed then change in device.rb 
			#
			@status = {}
			@status_lock = Mutex.new
			@status_emit = {}	# status => condition_variable
		end
		

		def logger
			@system.logger
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
