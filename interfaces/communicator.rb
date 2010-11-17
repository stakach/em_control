
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
		if system_list.includes?(system)
			@selected = system
		else
			raise "Invalid system selected"
		end
	end
	
	#
	# Pass commands to the selected system 
	#

end