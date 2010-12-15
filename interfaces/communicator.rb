
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
		@connected_interfaces = []
		@command_lock = Mutex.new

		@status_register = {}
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
	def self.select(interface, system)
		if system.class == Fixnum
			return System.systems[System.systems.keys[system]].communicator.attach(interface)
		else
			system = system.to_sym if system.class == String
			return System.systems[system].communicator.attach(interface)
		end
	end




	#
	# Keep track of connected systems
	#
	def disconnected(interface)
		@connected_interfaces.delete(interface)
	end


	#
	# Keep track of status events
	#
	def register(interface, mod, status)
		mod_sym = mod.to_sym if mod.class == String	# remember the symbol used by the interface to reference this module
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym]

		@status_register[mod] ||= {}
		@status_register[mod][status] ||= []
		@status_register[mod][status] << [interface, mod_sym]
		
		mod.add_observer(self)
	end

	def unregister(interface, mod, status)
		mod_sym = mod.to_sym if mod.class == String
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym]
		@status_register[mod][status] ||= []
		@status_register[mod][status].delete(interface)

		if @status_register[mod][status].empty?
			mod.delete_observer(self)
		end
	end

	def update(mod, status, data)
		return if @status_register[mod][status].nil?
		
		#
		# Interfaces should implement the notify function
		#
		@status_register[mod][status].each {|interface| interface[0].notify(interface[1], status, data) }
	end
	
	#
	# Pass commands to the selected system
	#
	def send(mod, command, *args, &block)
		#
		# Accept String, String (argument)
		#	String
		#
		mod = mod.to_sym if mod.class == String
		p "#{mod} #{command}"
		begin
			@command_lock.synchronize {
				@system.modules[mod].__send__(command, *args)	# Not send string however call function command
			}
		rescue
			begin
				block.call() if !block.nil?	# Block will inform of any errors
			rescue
			end
		end
	end
	

	def attach(interface)
		@connected_interfaces << interface unless @connected_interfaces.include?(interface)
		return self
	end


	protected


	def unregister_all(interface)
		# TODO
	end
end
end