class OrionLcd < Control::Device
	

	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:hex_string => true
		}
	end
	
	#def on_update
	#	logger.debug "-- Sharp LCD: !!UPDATED!!"
	#end
	
	def connected
		#do_poll
	
		#@polling_timer = periodic_timer(30) do
		#	logger.debug "-- Polling Display"
		#	do_poll
		#end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		#@polling_timer.cancel unless @polling_timer.nil?
	end
	
	#def response_delimiter
	#	0x0D	# Used to interpret the end of a message
	#end
	

	#
	# Power commands
	#
	def power(state)		
		if [On, "on", :on].include?(state)
			send('0A%0D%36%3B%34%3D%30%31%35%32%36%3E%0D')
			logger.debug "-- Orion LCD, requested to power on"
			self[:power] = On
		else
			send('0A%0D%36%3B%34%3D%30%31%35%32%36%36%0D')
			logger.debug "-- Orion LCD, requested to power off"
			self[:power] = Off
		end
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:dvi => '0A%0D%36%3B%34%3D%30%317369010101%0D',
		:svideo => '0A%0D%36%3B%34%3D%30%317373010101%0D',
		:video1 => '0A%0D%36%3B%34%3D%30%317376010101%0D',
		:dvd1 => '0A%0D%36%3B%34%3D%30%317364010101%0D',
		:component => '0A%0D%36%3B%34%3D%30%31%35%32%37%34%0D'	# DTV-YUV
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		
		send(INPUTS[input])
		self[:input] = input

		logger.debug "-- Orion LCD, requested to switch to: #{input}"
	end
	
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		send('0A%0D%36%3B%34%3D%30%317374010101%0D')
		logger.debug "-- Orion LCD, requested to auto adjust"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)		# Data is default recieved as a string
		logger.debug "-- Orion LCD, responded with 0x#{byte_to_hex(data)}"
		return :success
	end

end