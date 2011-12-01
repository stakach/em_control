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
		self[:iris_min] = 0x555
		self[:iris_max] = 0xFFF
		self[:pan_left_limit] = 0x2D08		# CCW Limit (Counter Clockwise)
		self[:pan_right_limit] = 0xD2F5		# CW Limit (Clockwise)
		self[:tilt_up_limit] = 0x5556
		self[:tilt_down_limit] = 0x8E38
		self[:zoom_min] = 0x001
		self[:zoom_max] = 0x999
		self[:focus_near] = 0x555
		self[:focus_far] = 0x999
		
		base.default_send_options = {
			:max_waits => 10	# Panasonic camera controller sends alot of commands
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
			do_send(command, 0x01, :delay => 6)
			logger.debug "Camera, requested to power on"
		else
			do_send(command, 0x00)
			logger.debug "Camera, requested to power off"
		end
	end

	def power?
		do_send('O', '', :emit => :power)
	end
	

	#
	# Preset selection
	#
	def preset(input)
		input = input - 1

		if self[:power] == Off
			power On
		end

		do_send("R", input.to_s.rjust(2, '0'), :delay => 1)		
		logger.debug "Camera, requested to switch to: #{input + 1}"
	end
	
	
	def save_preset(number)
		do_send('M', number - 1)
		logger.debug "Camera, requested to save preset: #{number}"
	end


	def up
		level = self[:tilt]
		tilt(level - 1) if level > self[:tilt_up_limit]
	end

	def down
		level = self[:tilt]
		tilt(level + 1) if level < self[:tilt_down_limit]
	end

	def left
		level = self[:pan]
		pan(level - 1) if level > self[:pan_left_limit]
	end

	def right
		level = self[:pan]
		pan(level + 1) if level < self[:pan_right_limit]
	end
	
	def pan(level)
		do_send('APC', "#{level.to_s(16).rjust(4, '0')}#{self[:tilt].to_s(16).rjust(4, '0')}")
	end
	
	def tilt(level)
		do_send('APC', "#{self[:pan].to_s(16).rjust(4, '0')}#{level.to_s(16).rjust(4, '0')}")
	end
	

	def zoom_in
		level = self[:zoom]
		zoom(level + 1) if level < self[:zoom_max]
	end

	def zoom_out
		level = self[:zoom]
		zoom(level - 1) if level > self[:zoom_min]
	end
	
	def zoom(level)
		do_send('AXZ', "#{level.to_s(16).rjust(3, '0')}")
	end
	
	
	def iris_open
		level = self[:iris]
		iris(level + 1) if level < self[:iris_max]
	end

	def iris_close
		level = self[:iris]
		iris(level - 1) if level > self[:iris_min]
	end
	
	def iris(level)
		do_send('AXZ', "#{level.to_s(16).rjust(3, '0')}")
	end
	
	def iris_mode(mode)
		if mode == :auto
			do_send('D3', '1')
		else	# mode == :manual
			do_send('D3', '0')
		end
	end
	
	
	def focus_near
		level = self[:focus]
		focus(level - 1) if level > self[:focus_near]
	end
	
	def focus_far
		level = self[:focus]
		focus(level + 1) if level < self[:focus_far]
	end
	
	def focus(level)
		do_send('AXF', "#{level.to_s(16).rjust(3, '0')}")
	end
	

	#
	# LCD Response code
	#
	def received(data, command)

		#logger.debug "Camera, sent #{data}"

		case data[0]
		when 'p' 	# Power
			if data[2] != 'S'				# pS == Pan Speed
				if data[1] =~ /1|n|2/
					self[:power] = On
				else
					self[:power] = Off
				end
				
				return :success if command[:data][1] == 'O'
			end
		when 's'	# preset call
			if data[1] != 'W'				# sWZ == Speed with zoom
				self[:preset] = data[1..-1].to_i + 1
				do_poll
				
				return :success if command[:data][0..1] =~ /^#R$|^#M$/
			end
		when 'a'
			case data[2]
			when 'C'			# PanTilt
				self[:pan] = data[3..6].to_i(16)
				self[:tilt] = data[6..10].to_i(16)
				
				return :success if command[:data][1..3] == 'APC'
			when 'z'			# Zoom
				self[:zoom] = data[3..-1].to_i(16)
				
				return :success if command[:data][1..3] == 'AXZ'
			when 'i'			# IRIS
				self[:iris] = data[3..-1].to_i(16)
				
				return :success if command[:data][1..3] == 'AXI'
			when 'f' 			# Focus
				self[:focus] = data[3..-1].to_i(16)
				
				return :success if command[:data][1..3] == 'AXF'
			end
		when 'd'
			case data[1]
			when '3' 	# Iris mode
				self[:iris_mode] = data[2] == '1' ? :auto : :manual
				
				return :success if command[:data][1..2] == 'D3'
			end
			
		when 'r'	# Error Status
			err = data[3..-1].to_i(16)
			if err > 0
				self[:error] = ERRORS[err]
			end
			
			return :success if command[:data][1..3] == 'RER'
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
		logger.debug "Camera, polling"
		zoom_status
		focus_status
		iris_status
		pantilt_status
		error_status
		power_status
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
		:zoom_status => 'AXZ',
		:focus_status => 'AXF',
		:iris_status => 'AXI',
		:pantilt_status => 'APC'
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
			do_send(message, '', {:priority => priority})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data, options = {})
		send("##{command}#{data}\r", options)
	end
end