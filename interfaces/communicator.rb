
#
# There should be one communicator per system that handles the interface interfaces
#	This will pass on registered status requirements and call functions as requested
#
#	Interfaces will have to have a base class that abstracts the event machine code so that
#	nothing runs on the reactor thread.
#
class Communicator
	
	#
	# Systems avaliable to this communicator
	#
	def system_list
		System.systems.keys
	end
	
	#
	# Set the system to communicate with
	#
	def select(system)
		if system.class == Fixnum
			@selected = System.systems[System.systems.keys[system]]
		else
			system = system.to_sym if system.class == String
			@selected = System.systems[system]
		end
	end
	
	#
	# Pass commands to the selected system
	#
	def send(command, *args)
		#
		# Accept String, String (argument)
		#	String
		#
		
	end
end