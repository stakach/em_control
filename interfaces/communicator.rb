
#
# There should be one communicator per system that handles the interface interfaces
#	This will pass on registered status requirements and call functions as requested
#
#	Interfaces will have to have a base class that abstracts the event machine code so that
#	nothing runs on the reactor thread.
#
module Control
class Communicator

	def initialize(system)
		@system = system
	end

	
	#
	# Systems avaliable to this communicator
	#
	def self.system_list
		System.systems.keys
	end
	
	#
	# Set the system to communicate with
	#	Up to interfaces to maintain stability here (They should deal with errors)
	#
	def self.select(system)
		if system.class == Fixnum
			return @selected = System.systems[System.systems.keys[system]].communicator
		else
			system = system.to_sym if system.class == String
			return @selected = System.systems[system].communicator
		end
	end
	
	#
	# Pass commands to the selected system
	#
	def send(mod, command, *args)
		#
		# Accept String, String (argument)
		#	String
		#
		@selected.modules[mod].__send__(command, *args)
	end
end
end