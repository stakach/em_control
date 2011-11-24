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
# volume
# volume_min == 0
# volume_max
#
# brightness
# brightness_min == 0
# brightness_max
#
# contrast
# contrast_min = 0
# contrast_max
# 
# audio_mute
# 
# input (video input)
# audio (audio input)
#
#
class LgLcd < Control::Device

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
		self[:volume_min] = 0
		self[:volume_max] = 100
		self[:brightness_min] = 0
		self[:brightness_max] = 100
		self[:contrast_min] = 0
		self[:contrast_max] = 100
	end
	
	def connected
		do_poll
	
		@polling_timer = periodic_timer(30) do
			logger.debug "Polling Display"
			do_poll
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
		'x'
	end
	

	#
	# Power commands
	#
	def power(state)
		command = 'ka'
		
		if [On, "on", :on].include?(state)
			do_send(command, 0x01)
			self[:warming] = true
			self[:power] = On
			logger.debug "LG LCD, requested to power on"
		else
			do_send(command, 0x00)
			self[:power] = Off
			logger.debug "LG LCD, requested to power off"
		end
		
		mute_status(0)
		volume_status(0)
	end
	
	def power_on?
		do_send('ka', 0xFF, :emit => :power)
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:tv => [0],			# DTV in manual
		:vga => [96],		# RGB in manual
		:component => [64],
		:hdmi => [112, 128, 144, 160],
		
		0 => :tv,
		96 => :vga,
		64 => :component,
		112 => :hdmi,
		128 => :hdmi,
		144 => :hdmi,
		160 => :hdmi
	}
	INPUT_NUMBER = {
		0 => 1,
		1 => 2,
		2 => 3,
		3 => 4
	}
	def switch_to(input)
		input = input.to_s if input.class == Symbol
		
		val = input.delete("^0-9")
		input = input.delete("0-9").to_sym
		
		if val.length > 0
			do_send('xb', INPUTS[input] & INPUT_NUMBER[val.to_i])
		else
			do_send('xb', INPUTS[input])
		end
		
		brightness_status(10)		# higher status than polling commands - lower than input switching
		contrast_status(10)

		logger.debug "LG LCD, requested to switch to: #{input}"
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		do_send('ju', 0x01, :delay_on_recieve => 3.0)
	end
	

	#
	# Value based set parameter
	#
	def brightness(val)
		val = 100 if val > 100
		val = 0 if val < 0
		
		do_send('kh', val)
	end
	
	def contrast(val)
		val = 100 if val > 100
		val = 0 if val < 0
		
		do_send('kg', val)
	end
	
	def volume(val)
		val = 100 if val > 100
		val = 0 if val < 0
		
		do_send('kf', val)
		self[:audio_mute] = false	# audio is unmuted when the volume is set
	end
	
	def mute
		do_send('ke', 0x01)
		
		logger.debug "LG LCD, requested to mute audio"
	end
	
	def unmute
		do_send('ke', 0x00)
		
		logger.debug "LG LCD, requested to unmute audio"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)
		
		data = data.split(' ')
		status = data[2][0..1]
		response = data[2].getbyte(2)
		
		logger.debug "LG LCD, sent command #{data[0]}: resp #{response}"
		
		if status == 'OK'
			case data[0]
				when 'a'	# Power
					one_shot(5) do				# Reactive the interface once the display is online
						self[:warming] = false	# allow access to the display
					end
				#when 'd'	# Video mute
				when 'e'	# Volume mute
					self[:audio_mute] = response == 1
				when 'f'	# Volume
					if not self[:audio_mute]
						self[:volume] = response
					end
				when 'g'	# Contrast
					self[:contrast] = response
				when 'h'	# Brightness
					self[:brightness] = response
				#when 'u'	# Auto config
				when 'b'	# Input
					port = response & 0xF0
					number = response & 0x0F
					if number > 0
						self[:input] = "#{INPUTS[port]}#{number}".to_sym
					else
						self[:input] = INPUTS[port]
					end
			end
		else
			if data[2] == 0
				return :abort	# invalid send (don't retry)
			else
				return :failed	# retry command
			end
		end
		
		return :success # Command success
	end
	

	def do_poll
		power_status
		mute_status
		volume_status
		brightness_status
		contrast_status
		video_input
	end


	private
	

	OPERATION_CODE = {
		:power_status => 'ka',
		:video_input => 'xb',
		:volume_status => 'kf',
		:mute_status => 'ke',
		:contrast_status => 'kg',
		:brightness_status => 'kh'
	}
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	OPERATION_CODE.each_key do |command|
		define_method command do |*args|
			priority = 99
			if args.length > 0
				priority = args[0]
			end
			message = OPERATION_CODE[command]
			do_send(message, 0xFF, {:priority => priority})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data, options = {})
		command = "" << command << ' ' << 0x00 << ' ' << data << "\r"
		send(command, options)
	end
end