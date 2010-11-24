
module Control
	class Modules
		@@last
		@@connection_information = {}

		def initialize
			@module_list = []
			@module_map = {}
			@name_map = {}
		end	


		
		def self.connections
			@@connection_information
		end

		#
		# mod lookup
		#
		def [] (mod)
			if mod.class == Fixnum
				@module_list[mod]
			else
				@module_map[mod]
			end
		end
	

		#
		# Map mods name(s) to mods
		#
		def []= (mod_id, mod)
			if mod_id.class == Fixnum
				@module_list[mod_id] = mod
			else
				@module_map[mod_id] = mod
				@name_map[mod] = [] if @name_map[mod] == nil
				@name_map[mod] << mod_id
			end
		end
		
		#
		# Get names mapped to a mod
		#
		def names(mod)
			@name_map[mod]
		end

		#
		# Add mod to the list (load order)
		#
		def << (mod)
			@module_list << mod
			@@last = mod
		end
	

		#
		# Get the last mod to be loaded
		#
		def self.last
			@@last
		end
	end
end
