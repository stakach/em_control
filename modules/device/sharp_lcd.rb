# :title:All Sharp Control Module
#
# Controls all LCD displays as of 1/10/2011
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# power
# warming
# power_on_delay
#
# volume
# volume_min == 0
# volume_max == 31
#
# brightness
# brightness_min == 0
# brightness_max == 31
#
# contrast
# contrast_min == 0
# contrast_max == 60
# 
# audio_mute
# 
# input (video input)
# audio (audio input)
#
#
class SharpLcd < Control::Device
	DelayTime = 1.0 / 9.0	# Time of 111ms from recieve before next send
	

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
		self[:volume_max] = 31
		self[:brightness_min] = 0
		self[:brightness_max] = 31
		self[:contrast_min] = 0
		self[:contrast_max] = 60	# multiply by two when VGA selected
		#self[:error] = []		TODO!!
		
		base.default_send_options = {
			:delay_on_recieve => DelayTime,		# Delay time required between commands
			:clear_queue_on_disconnect => true,	# Clear the queue as we need to send login
			:retry_on_disconnect => false		# Don't retry last command sent
		}
		@poll_lock = Mutex.new
	end
	
	#def on_update
	#	logger.debug "-- Sharp LCD: !!UPDATED!!"
	#end
	
	def connected
		do_send(setting(:username))
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@poll_lock.synchronize {
			@polling_timer.cancel unless @polling_timer.nil?
		}
	end
	
	def response_delimiter
		[0x0D, 0x0A]	# Used to interpret the end of a message
	end
	

	#
	# Power commands
	#
	def power(state)
		delay = self[:power_on_delay] || 5
		
		if [On, "on", :on].include?(state)
			#self[:power_target] = On
			if !self[:power]
				do_send('POWR   1', :timeout => delay + 15)
				self[:warming] = true
				self[:power] = On
				logger.debug "-- Sharp LCD, requested to power on"
				power_on?
			end
		else
			#self[:power_target] = Off
			if self[:power]
				do_send('POWR   0', :timeout => 15)
				
				self[:power] = Off
				logger.debug "-- Sharp LCD, requested to power off"
			end
		end
		
		mute_status(0)
		volume_status(0)
	end
	
	def power_on?
		do_send('POWR????', {:emit => :power, :timeout => 10, :value_ret_only => :POWR})
	end
	
	
	#
	# Resets the brightness and contrast settings
	#
	def reset
		do_send('ARST   2')
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:dvi => 'INPS   1', 1 => :dvi,
		:hdmi => 'INPS   9', 9 => :hdmi,
		:vga => 'INPS   2', 2 => :vga,
		:component => 'INPS   3', 3 => :component
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		
		#self[:target_input] = input
		do_send(INPUTS[input], :timeout => 20)	# does an auto adjust on switch to vga
		video_input(0)	# high level command
		brightness_status(60)		# higher status than polling commands - lower than input switching (vid then audio is common)
		contrast_status(60)

		logger.debug "-- Sharp LCD, requested to switch to: #{input}"
	end
	
	AUDIO = {
		:audio1 => 'ASDP   2',
		:audio2 => 'ASDP   3',
		:dvi => 'ASDP   1',
		:hdmi => 'ASHP   0',
		:vga => 'ASAP   1',
		:component => 'ASCA   1'
	}
	def switch_audio(input)
		input = input.to_sym if input.class == String
		self[:audio] = input
		
		do_send(AUDIO[input])
		mute_status(0)		# higher status than polling commands - lower than input switching
		#volume_status(60)	# Mute response requests volume
		
		logger.debug "-- Sharp LCD, requested to switch audio to: #{input}"
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		do_send('AGIN   1', :timeout => 20)
	end
	

	#
	# Value based set parameter
	#
	def brightness(val)
		val = 31 if val > 31
		val = 0 if val < 0
		
		message = "VLMP"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
	end
	
	def contrast(val)
		val = 60 if val > 60
		val = 0 if val < 0
		
		val = val * 2 if self[:input] == :vga		# See sharp Manual
		
		message = "CONT"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
	end
	
	def volume(val)
		val = 31 if val > 31
		val = 0 if val < 0
		
		message = "VOLM"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
		
		self[:audio_mute] = false	# audio is unmuted when the volume is set (TODO:: check this)
	end
	
	def mute
		do_send('MUTE   1')
		mute_status(0)	# High priority mute status
		
		logger.debug "-- Sharp LCD, requested to mute audio"
	end
	
	def unmute
		do_send('MUTE   0')
		mute_status(0)	# High priority mute status
		
		logger.debug "-- Sharp LCD, requested to unmute audio"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)		# Data is default recieved as a string
		
		#logger.debug "-- Sharp LCD, recieved: #{data}"
		
		value = nil
		
		
		if data == "Login:"
			do_send(setting(:password), :delay_on_recieve => 5.0)
			return true
		elsif data == "Password:OK"
			do_poll
			
			@poll_lock.synchronize {
				@polling_timer = periodic_timer(30) do
					logger.debug "-- Polling Display"
					do_poll unless self[:warming]
				end
			}
		elsif data == "Password:Login incorrect"
			logger.info "Sharp LCD, bad login or logged off. Attempting login.."
			do_send(setting(:username))
			return true
		elsif data == "OK"
			return true
		elsif data == "WAIT"
			logger.debug "-- Sharp LCD, wait"
			return nil
		elsif data == "ERR"
			logger.debug "-- Sharp LCD, error"
			return false
		end
			
		if command.nil?
			if data.length < 8		# Out of order send?
				logger.info "Sharp sent out of order response: #{data}"
				return :fail		# this will be ignored
			end
			command = data[0..3].to_sym
			value = data[4..7].to_i
		else
			value = data.to_i
			command = command[:value_ret_only]
		end
		
		case command
			when :POWR # Power status
				self[:warming] = false
				self[:power] = value > 0
				#logger.debug "-- Sharp LCD, power value #{value > 0}"
			when :INPS # Input status
				self[:input] = INPUTS[value]
				#logger.debug "-- Sharp LCD, input #{INPUTS[value]}"
			when :VOLM # Volume status
				if not self[:audio_mute]
					self[:volume] = value
					#logger.debug "-- Sharp LCD, volume #{value}"
				end
			when :MUTE # Mute status
				self[:audio_mute] = value == 1
				if(value == 1)
					self[:volume] = 0
				else
					volume_status(0)	# high priority
				end
				#logger.debug "-- Sharp LCD, muted #{value == 1}"
			when :CONT # Contrast status
				value = value / 2 if self[:input] == :vga
				self[:contrast] = value
				#logger.debug "-- Sharp LCD, contrast #{value}"
			when :VLMP # brightness status
				self[:brightness] = value
				#logger.debug "-- Sharp LCD, brightness #{value}"
			when :PWOD
				self[:power_on_delay] = value
				#logger.debug "-- Sharp LCD, power on delay #{value}s"
		end
		
		return true # Command success?
	end
	

	def do_poll
		do_send('POWR????', {:timeout => 10, :value_ret_only => :POWR, :priority => 99})
		power_on_delay
		video_input
		#power_on?	# no emits on recieve!!
		#audio_input
		mute_status
		brightness_status
		contrast_status
	end


	private
	

	OPERATION_CODE = {
		:video_input => 'INPS????',
		#:audio_input => 'ASDP????',	# This would have to be a regular function (too many return values and polling values)
		:volume_status => 'VOLM????',
		:mute_status => 'MUTE????',
		:power_on_delay => 'PWOD????',
		:contrast_status => 'CONT????',
		:brightness_status => 'VLMP????',
	}
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	OPERATION_CODE.each_pair do |command, value|
		define_method command do |*args|
			priority = 99
			if args.length > 0
				priority = args[0]
			end
			#logger.debug "Sharp sending: #{command}"
			do_send(value.clone, {:priority => priority, :value_ret_only => value[0..3].to_sym})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and creates the checksum
	#
	def do_send(command, options = {})
		command = command.clone
		command << 0x0D << 0x0A
		
		send(command, options)
	end
end