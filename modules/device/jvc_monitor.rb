# :title:JVC Display Control Module
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# power
# 
# audio_mute
# 
# input (video input)
#
#
class JvcMonitor < Control::Device
	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def on_load		
		base.default_send_options = {
			:retry_on_disconnect => false		# Don't retry last command sent
		}
	end
	
	#def on_update
	#	logger.debug "-- JVC LCD: !!UPDATED!!"
	#end
	
	def connected
		do_send('CN1')	# Connection command - initiate comms
	
		@polling_timer = periodic_timer(60) do
			logger.debug "Polling JVC"
			do_send('CN1')	# Connection command
		end
	end

	def disconnected
		@polling_timer.cancel unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	def response_delimiter
		0x0D
	end
	

	#
	# Power commands
	#
	def power(state)
		if [On, "on", :on].include?(state)
			com = 'PW1'
			logger.debug "-- JVC LCD, requested to power on"
		else
			com = 'PW0'
			logger.debug "-- JVC LCD, requested to power off"
		end
		
		do_send(com, {:timeout => 8}) do |data, command|
			if data =~ /OK/
				self[:power] = com == 'PW1'
				:success
			else
				:failed
			end
		end
	end
	
	def power_on?
		self[:power]
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:sdi => 'INA',
		:sdi1 => 'INA',
		:sdi2 => 'INB',
		:dvi => 'INC',
		:video => 'INE',
		:video1 => 'INE',
		:video2 => 'INF'
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		
		do_send(INPUTS[input], {:timeout => 5}) do |data, command|
			if data =~ /OK/
				self[:input] = input
				:success
			else
				:failed
			end
		end

		logger.debug "-- JVC LCD, requested to switch to: #{input}"
	end
	
	def mute
		do_send('AMUTE01') do |data, command|
			if data =~ /OK/
				self[:mute] = true
				:success
			else
				:failed
			end
		end
		
		logger.debug "-- JVC LCD, requested to mute video"
	end
	
	def unmute
		do_send('AMUTE00') do |data, command|
			if data =~ /OK/
				self[:mute] = false
				:success
			else
				:failed
			end
		end
		
		logger.debug "-- JVC LCD, requested to unmute video"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)		# Data is default received as a string
		
		#logger.debug "-- JVC LCD, received: #{data}"
		:success
	end


	private
	

	#
	# Builds the command and creates the checksum
	#
	def do_send(command, options = {}, &block)
		command = "!00B#{command}\r"
		
		send(command, options, &block)
	end
end