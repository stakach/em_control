class PanasonicHe870 < Control::Device

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
		self[:pan_ccw] = 0x2D08		# Counter Clock Wise
		self[:pan_cw] = 0xD2F5
		
		self[:tilt_up] = 0x5556
		self[:tilt_down] = 0x8E38
		
		self[:zoom_min] = 1
		self[:zoom_max] = 999
		
		self[:focus_near] = 1
		self[:focus_far] = 999
		
		self[:iris_close] = 1
		self[:iris_open] = 999

		self[:speed_max] = 49
		self[:speed_min] = 1

		self[:pan_speed] = 10
		self[:tilt_speed] = 10
		self[:focus_speed] = 10
		self[:zoom_speed] = 10
		
		base.default_send_options = {
			:max_waits => 10,	# Panasonic camera controller sends alot of commands
			:wait => false
		}
	end
	
	def connected
		do_poll
	
		@polling_timer = periodic_timer(60) do
			logger.debug "Polling Camera"
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
		/\r|\x03/
	end
	

	#
	# Power commands
	#
	def power(state)
		command = "O"
		
		if [On, "on", :on].include?(state)
			do_send(command, 0x01, :delay => 6, :wait => true)
			logger.debug "Camera, requested to power on"
		else
			do_send(command, 0x00, :wait => true)
			logger.debug "Camera, requested to power off"
		end
	end

	def power?
		do_send('O', '', :emit => :power, :wait => true)
	end
	

	#
	# Preset selection
	#
	def preset(input)
		input = input - 1

		if self[:power] == Off
			power On
		end

		do_send("R", input.to_s.rjust(2, '0'), :delay => 1, :wait => true)		
		logger.debug "Camera, requested to switch to: #{input + 1}"
	end
	
	
	def save_preset(number)
		do_send('M', number - 1, :wait => true)
		logger.debug "Camera, requested to save preset: #{number}"
	end


	def tilt_speed(speed)
		self[:tilt_speed] = speed
	end


	def tilt_up(speed = self[:tilt_speed])
		speed += 50
		do_send('T', speed.to_s.rjust(2,'0'))
	end

	def tilt_down(speed = self[:tilt_speed])
		speed = 50 - speed
		do_send('T', speed.to_s.rjust(2,'0'))
	end

	def tilt_stop
		do_send('T', 50)
	end

	def pan_speed(speed)
		self[:pan_speed] = speed
	end


	#
	# Must poll these
	#
	def pan_right(speed = self[:pan_speed])
		speed += 50
		do_send('P', speed.to_s.rjust(2,'0'))
	end

	def pan_left(speed = self[:pan_speed])
		speed = 50 - speed
		do_send('P', speed.to_s.rjust(2,'0'))
	end
	
	def pan_stop
		do_send('P', 50)
	end
	
	
	#
	# Default == center
	#
	def pantilt(pan = 0x8000, tilt = 0x8000)
		do_send('APC', "#{pan.to_s(16).rjust(4, '0')}#{tilt.to_s(16).rjust(4, '0')}", :wait => true)
	end
	
	def pan(position)
		pantilt(position, self[:tilt])
	end
	
	def tilt(position)
		pantilt(self[:pan], position)
	end
	
	
	LIMIT_CONTROLS = {
		:up => 1,
		:down => 2,
		:left => 3,
		:right => 4
	}
	def limit(direction, type = :set)
		direction = direction.to_sym if direction.class == String
		type = type == :set ? 1 : 0
		do_send('LC', "#{LIMIT_CONTROLS[direction]}#{type}")
	end
	

	def zoom_speed(speed)
		self[:zoom_speed] = speed
	end

	def zoom_in(speed = self[:zoom_speed])
		speed += 50
		do_send('Z', speed.to_s.rjust(2,'0'))
	end

	def zoom_out(speed = self[:zoom_speed])
		speed = 50 - speed
		do_send('Z', speed.to_s.rjust(2,'0'))
	end

	def zoom_stop
		do_send('Z', 50)
	end
	
	def zoom(position)
		do_send('AYZ', position.to_s.rjust(3,'0'), :wait => true)
	end
	
	
	
	def iris(level)
		do_send('I', level.to_s.rjust(2,'0'))
	end
	
	def iris_mode(mode)
		if mode == :auto
			do_send('D3', '1')
		else	# mode == :manual
			do_send('D3', '0')
		end
	end
	
	def iris(position)
		do_send('AYI', position.to_s.rjust(3,'0'), :wait => true)
	end
	
	
	def focus_speed(speed)
		self[:focus_speed] = speed
	end

	def focus_near(speed = self[:focus_speed])
		speed += 50
		do_send('F', speed.to_s.rjust(2,'0'))
	end
	
	def focus_far(speed = self[:focus_speed])
		speed = 50 - speed
		do_send('F', speed.to_s.rjust(2,'0'))
	end
	
	def focus_stop
		do_send('F', 50)
	end
	
	def focus(position)
		do_send('AYF', position.to_s.rjust(3,'0'), :wait => true)
	end
	

	#
	# LCD Response code
	#
	def received(data, command)

		#logger.debug "Camera, sent #{data}" unless command.nil?

		case data[0]
		when 'p' 	# Power
			if data[2] != 'S'				# pS == Pan Speed
				if data[1] =~ /1|n|2/
					self[:power] = On
				else
					self[:power] = Off
				end
				
				return :success if command.present? && command[:data][1] == 'O'
			end
		when 's'	# preset call
			if data[1] != 'W'				# sWZ == Speed with zoom
				preset = data[1..-1].to_i + 1
				if preset != self[:preset]
					do_poll
				end
				self[:preset] = preset
				
				
				return :success if command.present? && command[:data][0..1] =~ /^#R$|^#M$/
			end
		when 'a'
			case data[2]
			when 'C'			# PanTilt
				self[:pan] = data[3..6].to_i(16)
				self[:tilt] = data[6..10].to_i(16)
				
				return :success if command.present? && command[:data][1..3] == 'APC'
			when 'z'			# Zoom
				self[:zoom] = (data[3..-1].to_i(16) - 0x554)
				
				return :success if command.present? && command[:data][1..3] == 'AYZ'
			when 'i'			# IRIS
				self[:iris] = data[3..-1].to_i(16)
				
				return :success if command.present? && command[:data][1..3] == 'AXI'
			when 'f' 			# Focus
				self[:focus] = data[3..-1].to_i(16)
				
				return :success if command.present? && command[:data][1..3] == 'AXF'
			end
		when 'g'
			case data[1]
			when 'z'
				self[:zoom] = data[2..-1].to_i(16)
				self[:power] = On
				
				return :success if command.present? && command[:data][1..2] == 'GZ'
			when 'f'
				self[:focus] = data[2..-1].to_i(16)
				
				return :success if command.present? && command[:data][1..2] == 'GF'
			when 'i'
				self[:iris] = data[2..-1].to_i(16)
				
				return :success if command.present? && command[:data][1..2] == 'GI'
			end
		when 'd'
			case data[1]
			when '3' 	# Iris mode
				self[:iris_mode] = data[2] == '1' ? :auto : :manual
				
				return :success if command.present? && command[:data][1..2] == 'D3'
			end
			
		when 'r'	# Error Status
			err = data[3..-1].to_i(16)
			if err > 0
				self[:error] = ERRORS[err]
			end
			
			return :success if command.present? && command[:data][1..3] == 'RER'
		when '-'
			self[:power] = Off
			return :success
		end
		
		#
		# Default is ignore as if a controller is connected
		# 	it requests alot of data
		#
		return :ignore
	end
	

	def do_poll
		#logger.debug "Camera, polling"
		zoom_status
		#focus_status
		#iris_status
		##pantilt_status
		error_status
		##power_status use GZ command - if response is '---' then power is off
	end


	private
	
	
	ERRORS = {
		3 => [3, "Motor Driver Error"],
		4 => [4, "Pan Sensor Error"],
		5 => [5, "Tilt Sensor Error"],
		6 => [6, "Controller RX Over run Error"],
		7 => [7, "Controller RX Framing Error"],
		8 => [8, "Network RX Over run Error"],
		9 => [9, "Network RX Framing Error"],
		23 => [23, "Controller RX Command Buffer Overflow"],
		25 => [25, "Network RX Command Buffer Overflow"],
		27 => [27, "System Error"],
		28 => [28, "Spec Limit Over"],
		29 => [29, "FPGA Config Error"],
		30 => [30, "Network Communication Error"]
	}
	

	OPERATION_CODE = {
		:power_status => 'O',
		:zoom_status => 'GZ',
		:focus_status => 'GF',
		:iris_status => 'GI',
		:pantilt_status => 'APC',
		:error_status => 'RER'
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
			do_send(message, '', {:priority => priority, :wait => true})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data, options = {})
		send("##{command}#{data}\r", options)
	end
end