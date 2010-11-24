
module Control
	class System

		@@systems = {}
		
		def self.systems
			@@systems
		end

		def initialize(name)
			@name = name
			@modules = Modules.new

			@@systems[name] = self
		end

		attr_accessor :modules
		attr_accessor :interfaces
		attr_reader :name
	
	end
end
