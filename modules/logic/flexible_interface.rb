#
# For use with the example interface to demonstrate how to interact with interfaces
#
class FlexiInterface < Control::Logic

	#
	# Module callbacks
	#
	def on_load
		#
		# Setup constants
		#
		self[:volume_max] = 100
		self[:volume_min] = 0
		
		self[:display] = Off
		self[:screen] = :up
		
		self[:page] = :start
	end
	
	
	def on_unload
	end
	
	
	def on_update
	end
	
	
	#
	# Custom functions
	#	Of course these would usually communicate to physicall devices to portray this information
	#	and only update the status when the device responds
	#
	def page(name)
		name = name.to_sym
		if [:start, :home, :audio, :lights, :other].include?(name)
			self[:page] = name
		end
	end
	
	def display(input)
		self[:display] = input.to_sym
	end
	
	def preview(input)
		self[:preview] = input.to_sym
	end
	
	def audio(input)
		self[:audio] = input.to_sym
	end
	
	def volume(value)
		self[:volume] = value.to_i
	end
	
	def light(level)
		self[:light] = level.to_sym
	end
	
	def power(state)
		if [On, 'on', :on].include?(state)
			self[:power] = :on
		else
			self[:power] = :off
		end
	end
	
	def screen(state)
		if [false, 'up', :up].include?(state)
			self[:screen] = :up
		else
			self[:screen] = :down
		end
	end

end
