#
# (Settings)
#	* in-house-pc (input name)
#	* audio1 (in-house-pc audio input name)
#	* laptop1 (input name)
#	* laptop2 (input name)
#	* audio2 (laptop1 and 2 audio input name)
#	* collaboration_page (address of web page to load for collaboration)
#
# (module defined)
# input
#
class PodControl < Control::Logic


	def on_load
		#
		# Setup constants
		#
		self[:laptop1] = setting(:laptop1)
		self[:laptop2] = setting(:laptop2)
		register(:Display, :input)	# expects display_input_change
	end
	
	
	def on_update
		self[:laptop1] = setting(:laptop1)
		self[:laptop2] = setting(:laptop2)
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
	

	def start_collaborating
		system[:Computer].launch_application(setting(:collaboration_page))
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
