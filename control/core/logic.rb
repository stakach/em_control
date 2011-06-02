

module Control

	#
	# Base class for all control logic classes
	#
	class Logic
		include Status
		include Constants
		include Utilities
		
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
		

		def setting(name)
			LogicModule.lookup[self]
		end
		

		attr_reader :system
		
		
		def register(mod, status, &block)
			@system.communicator.register(self, mod, status, &block) 
		end
		
		def unregister(mod, status, &block)
			@system.communicator.unregister(self, mod, status, &block) 
		end

		
	end
end
