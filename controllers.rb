

module Control
	class Controllers
	
		def initialize
			@control_list = []
			@control_map = {}
		end	


		#
		# control lookup
		#
		def [] (control)
			if control.class == Fixnum
				@control_list[control]
			else
				@control_map[control]
			end
		end
	

		#
		# Map controls name(s) to controls
		#
		def []= (control_id, control)
			if control_id.class == Fixnum
				@control_list[control_id] = control
			else
				@control_map[control_id] = control
			end
		end


		#
		# Add control to the list (load order)
		#
		def << (control)
			@control_list << control
		end
	end
end
