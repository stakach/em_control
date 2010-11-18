

module Control
	module Utilities
		def hex_to_b(data)	# Assumes string - converts to binary string
			data.gsub!(/(0x|[^0-9A-Fa-f])*/, "")
			
		end
	end
end