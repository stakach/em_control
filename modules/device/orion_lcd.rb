
# :title:LG LCD Control Module
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# power
# warming
#
# video_mute
# 
# input (video input)
#
#
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
	end
	
	def connected
		self[:power] = Off
	
		@polling_timer = periodic_timer(60) do
			logger.debug "Polling Orion"
			do_send('FCDR', '000', {:priority => 99, :wait => false})	# Status polling is a low priority
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	def response_delimiter
		"\r"
	end
	

	#
	# Power commands
	#
	def power(state)
		command = 'PWRW'
		
		if [On, "on", :on].include?(state)
			do_send(command, '-ON', :delay => 7)
			logger.debug "LG LCD, requested to power on"
		else
			do_send(command, 'OFF')
			logger.debug "LG LCD, requested to power off"
		end
		
		unmute_video
	end
	
	def power_on?
		self[:power]
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:vga => '-PC',		# PC or D-SUB in manual
		:component => 'COM',
		:hdmi => 'DVI',
		:svideo => 'SAV',
		:composite => '-AV',
		
		'-PC' => :vga,
		'COM' => :component,
		'DVI' => :hdmi,
		'SAV' => :svideo,
		'-AV' => :composite
	}
	def switch_to(input, options = {})
		input = input.to_sym if input.class == String
		
		do_send('MINW', INPUTS[input], options)
	end
	
	
	KEYS = {
		:up => '-UP',
		:down => 'DOW',
		:left => 'LEF',
		:right => 'RIG',
		:volume_up => 'RIG',
		:volume_down => 'LEF',
		:menu => 'MEN',
		:source => 'SOU',
		:enter => 'ENT',
		:exit => 'EXI'
	}
	def remote(key)
		key = key.to_sym if key.class == String
		do_send('RMTW', KEYS[key])
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		if self[:input] == :vga
			do_send('AUTW', '-PC', :delay_on_recieve => 3.0)
		end
	end
	
	def mute_video
		do_send('MUTW', '-ON')
		
		logger.debug "Orion LCD, requested to mute video"
	end
	
	def unmute_video
		do_send('MUTW', 'OFF')
		
		logger.debug "Orion LCD, requested to unmute video"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)
		
		#
		# Get start of text
		#
		data = data.split("\x0F")
		if data.length >= 2
			data = data[-1]	# valid response
		else
			return :ignore	# Invalid data (we shall ignore)
		end
		
		#
		# Extract status value
		#
		data = data.split('#')
		if data.length >= 2
			status = data[0][3..-1].to_sym	# 001PWR => PWR
			response = data[1]
		else
			logger.debug "Orion LCD, failed with #{data.inspect}"
			return :failed					# 001PWRERROR
		end
		
		#logger.debug "Orion LCD, sent #{data}"
		
		case status
			when :PWR	# Power
				power = response == "-ON"
				
				if !self[:power] && power
					self[:warming] = true
					one_shot(6) do				# Reactive the interface once the display is online
						self[:warming] = false	# allow access to the display
					end
				end
				
				self[:power] = power
			when :MUT	# Video mute
				self[:video_mute] = response == "-ON"
			when :MIN	# Input
				self[:input] = INPUTS[response]
			when :AUT
			when :RMT
			else
				return :ignore	# We didn't request this data
		end
		
		return :success # Command success
	end


	private
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data, options = {})
		command = "\x0F001" << command << data << "0\r"
		send(command, options)
	end
end