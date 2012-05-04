
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
		
		
		def clear_active_timers
			@schedule.clear_jobs unless @schedule.nil?
		end

		
		protected
		

		def setting(name)
			val = LogicModule.lookup(self).settings.where("name = ?", name).first || LogicModule.lookup(self).control_system.zones.joins(:settings).where('settings.name = ?', name.to_s).first.settings.where("name = ?", name.to_s).first || LogicModule.lookup(self).dependency.settings.where("name = ?", name).first
			
			if !val.nil?
				case val.value_type
					when 0
						return val.text_value
					when 1
						return val.integer_value
					when 2
						return val.float_value
					when 3
						return val.datetime_value
				end
			end
			
			return nil
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
