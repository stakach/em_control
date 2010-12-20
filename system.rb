
module Control
	class System

		@@systems = {}
		
		def self.systems
			@@systems
		end
		
		def self.[] (system)
			@@systems[system]
		end

		def initialize(name)
			@name = name
			@modules = Modules.new
			@communicator = Communicator.new(self)

			@@systems[name] = self
		end
		
		def [] (mod)
			@modules[mod]
		end

		attr_reader :modules
		attr_reader :name
		attr_reader :communicator
	
	end
end
