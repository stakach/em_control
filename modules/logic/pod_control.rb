class PodControl < Control::Logic


	def onLoad
		#
		# Setup constants
		#
		self[:laptop1] = setting(:laptop1)
		self[:laptop2] = setting(:laptop2)
		register(:Display, :input)	# expects display_input_change
	end


	def select(input)
		#
		# Check the display is on.
		#	If not then power it on.
		#
		if !system[:Display].power_on?
			system[:Display].power(On)
		end
		
		#
		# Switch to the correct video source
		#	Based on the settings (input == 'in-house-pc' or 'laptop1' or 'laptop2')
		#
		system[:Display].switch_to(setting(input))
		self[:input] = input
		
		#
		# Switch to the correct audio source
		#
		if(input == 'in-house-pc')
			system[:Display].switch_audio(:audio1)
		else
			system[:Display].switch_audio(:audio2)
		end
	end
	
	#
	# This is because if the in house pc is off or unplugged
	#	The screen may change the input.
	#
	def display_input_changed(status)
		if system[:Display][:power]
			logger.debug "-- Pod input changed: #{status}"
			case status.to_s
				when setting('in-house-pc')
					self[:input] = 'in-house-pc'
				when setting('laptop1')
					self[:input] = :laptop1
				when setting('laptop2')
					self[:input] = :laptop2
				else
					select('in-house-pc')
			end
		end
	end


end
