
#
# Controls all NEC projectors as of 9/01/2011
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
# disconnected
#
# (module defined)
# error (array of strings)
#
# lamp_status
# lamp_target
# lamp_warming
# lamp_cooling
# lamp_usage (array of integers representing hours)
#
# volume
# volume_min == 0
# volume_max == 63
#
# zoom
# zoom_min
# zoom_max
# 
# mute (picture and audio)
# picture_mute
# audio_mute
# onscreen_mute
# picture_freeze
# 
# target_input
# input_selected
# 
# model_name
# model_series
#
#
class AllNec < Control::Device
	include Control::Utilities
	

	def initialize *args
		super	# Must be called
		
		#
		# Setup constants
		#
		self[:volume_min] = 0
		self[:volume_max] = 63
	end
	
	#
	# Connect and request projector status
	#
	def connected
		#
		# Get current state of the projector
		#
		do_poll
	end

	#def disconnected
		#
		# Perform any cleanup functions here
		#
	#end
	

	#
	# Volume Modification
	#
	def volume_up
		
	end
	
	def volume_down
		
	end
	
	def volume(vol)
		#					 D1  D2  D3   D4 D5 + CKS
		"03H 10H 00H 00H 05H 05H 00H 00H" # volume base command
		# D3 = 00 (absolute vol) or 01 (relative vol)
		# D4 = value (lower bits 0 to 63)
		# D5 = value (higher bits always 00h)
				
		
	end
	
	def mute_all
		mute_picture
		mute_audio
		mute_onscreen
	end
	
	def unmute_all
		unmute_picture
		unmute_audio
	end
	
	
	INPUTS = {
		:vga1 =>		0x01,
		:vga =>			0x01,
		:rgbhv =>		0x02,	# \
		:dvi_a =>		0x02,	#  } - all of these are the same
		:vga2 =>		0x02,	# /
		
		:composite =>	0x06,
		:svideo =>		0x0B,
		
		:component1 =>	0x10,
		:component =>	0x10,
		:component2 =>	0x11,
		
		:dvi =>			0x1A,	# \
		:hdmi =>		0x1A,	# | - These are the same
		
		:lan =>			0x20,
		:viewer =>		0x1F
	}
	
	def switch_input(input)
		input = input.to_sym if input.class == String
		
		#
		# Input status update
		#	As much for internal use as external
		#	and with the added benefit of being thread safe
		#
		self[:target_input] = input		# should do this for power on and off (ensures correct state)
		
		command = [0x02, 0x03, 0x00, 0x00, 0x02, 0x01]
		command << INPUTS[input]
		send_checksum(command)
	end

	
	#
	# Command Listing
	#
	COMMAND = {
		# Second byte used to detect command type
		:lamp_on =>			"$02,$00,$00,$00,$00,$02",
		:lamp_off =>		"$02,$01,$00,$00,$00,$03",
		
		# Mute controls
		:mute_picture =>	"$02,$10,$00,$00,$00,$12",
		:unmute_picture =>	"$02,$11,$00,$00,$00,$13",
		:mute_audio =>		"02H 12H 00H 00H 00H 14H",
		:unmute_audio =>	"02H 13H 00H 00H 00H 15H",
		:mute_onscreen =>	"02H 14H 00H 00H 00H 16H",
		:unmute_onscreen =>	"02H 15H 00H 00H 00H 17H",
		:freeze_picture =>	"$01,$98,$00,$00,$01,$01,$9B",
		:unfreeze_picture =>"$01,$98,$00,$00,$01,$02,$9C",
		
		:status_lamp =>		"00H 81H 00H 00H 00H 81H",		# Running sense (ret 81)
		:status_input =>	"$00,$85,$00,$00,$01,$02,$88",	# Input status (ret 85)
		:status_mute =>		"00H 85H 00H 00H 01H 03H 89H",	# MUTE STATUS REQUEST (Check 10H on byte 5)
		:status_error =>	"00H 88H 00H 00H 00H 88H",		# ERROR STATUS REQUEST (ret 88)
		:status_model =>	"00H 85H 00H 00H 01H 04H 8A",	# request model name (both of these are related)
		
		# lamp hours / remaining information
		:lamp_information =>"0x03 8CH 00H 00H 00H 8FH",		# LAMP INFORMATION REQUEST
		
		:background_black =>"$03,$B1,$00,$00,$02,$0B,$01,$C2",	# set mute to be a black screen
		:background_blue => "$03,$B1,$00,$00,$02,$0B,$00,$C1",	# set mute to be a blue screen
		:background_logo => "$03,$B1,$00,$00,$02,$0B,$02,$C3"	# set mute to be the company logo
	}
	

	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	COMMAND.each_key do |command|
		define_method command do
			send(COMMAND[command], :hex_string => true)
		end
	end


	#
	# Return true if command success, nil if still waiting, false if fail
	#
	def received(data)
		#
		# Command failed
		#
		if data[0] & 0xA0 == 0xA0
			#
			# We were changing power state at time of failure we should keep trying
			#
			if [0x00, 0x01].include?(last_command[1])
				sleep(5)
				status_lamp
				return true
			end
			logger.info "-- NEC projector, sent fail code for command: 0x#{byte_to_hex(array_to_str(last_command))}"
			logger.info "-- NEC projector, response was: 0x#{byte_to_hex(array_to_str(data))}"
			return false
		end
		
		#
		# Check checksum
		#
		if !check_checksum(data)
			logger.debug "-- NEC projector, checksum failed for command: 0x#{byte_to_hex(array_to_str(last_command))}"
			return false
		end

		#
		# Process a successful command
		#
		case data[1]
			when 0x00, 0x01
				return process_power_command(data)
			when 0x81
				return process_power_status(data)
			when 0x85
				case last_command[-2]
					when 0x02
						process_input_state(data)
						return true
					when 0x03
						process_mute_state(data)
						return true
				end
			when 0x10, 0x11, 0x12, 0x13, 0x14, 0x15
				status_mute	# update mute status's (dry)
				return true
			when 0x03
				return process_input_switch(data)
		end
		
		logger.warn "-- NEC projector, no status updates defined for response: #{byte_to_hex(array_to_str(data))}"
		logger.warn "-- NEC projector, command was: 0x#{byte_to_hex(array_to_str(last_command))}"
		return true											# to prevent retries on commands we were not expecting
	end
	
	
	private
	

	def do_poll
		status_lamp
		status_input
	end
	

	def process_power_command(data)
		last = last_command
		
		logger.debug "-- NEC projector sent a response to a power command"

		#
		# Ensure a change of power state was the last command sent
		#
		if last[1] == 0x00 || last[1] == 0x01
			if data[1] == 0x00
				self[:lamp_target] = On
			else
				self[:lamp_target] = Off
			end
			
			status_lamp	# Queues the status power command
		end
		
		return true												# Command success
	end
	
	def process_power_status(data)
		logger.debug "-- NEC projector sent a response to a power status command"	
		
		self[:lamp_status] = (data[-2] & 0b10) > 0x0	# Power on?

		if (data[-2] & 0b100000) > 0 || (data[-2] & 0b10000000) > 0
			# Projector cooling || power on off processing
			
			if self[:lamp_target] == On
				self[:lamp_cooling] = false
				self[:lamp_warming] = true
	
				logger.debug "lamp warming..."
						
	
			elsif self[:lamp_target] == Off
				self[:lamp_warming] = false
				self[:lamp_cooling] = true
				
				logger.debug "lamp cooling..."
			end

			sleep(3)											# pause this thread for 3 seconds
			status_lamp	# Then re-queue this command			

			#	Signal processing				external control
		elsif (data[-2] & 0b1000000) > 0 #|| (data[-2] & 0b10000) == 0
			sleep(2)
			status_lamp	# Then re-queue this command
		else
			#
			# We are in a stable state!
			#
			if self[:lamp_status] != self[:lamp_target]
				if self[:lamp_target].nil?
					self[:lamp_target] = self[:lamp_status]
				else
					logger.debug "NEC projector in an undesirable power state... (Correcting)"
					sleep(5)
					if self[:lamp_target] == On
						lamp_on
					elsif self[:lamp_target] == Off
						lamp_off
					end
				end
			else
				logger.debug "NEC projector is in a good power state..."

				status_input unless self[:lamp_status] == Off 	# calls status mute
			end
		end
		
		return true
	end
	
	
	INPUT_MAP = {
		0x01 => {
			0x01 => :vga,
			0x02 => :composite,
			0x03 => :svideo,
			0x06 => :hdmi,
			0x07 => :viewer
		},
		0x02 => {
			0x01 => :vga2,
			0x04 => :component2,
			0x07 => :lan
		},
		0x03 => {
			0x04 => :component
		}
	}
	def process_input_state(data)
		logger.debug "-- NEC projector sent a response to an input state command"
		return if self[:lamp_status] == Off		# no point doing anything here if the projector is off

		self[:input_selected] = INPUT_MAP[data[-15]][data[-14]]
		if data[-17] == 0x01
			sleep(2)	# still processing signal
			status_input
		else
			status_mute
		end

		#
		# Notify of bad input selection for debugging
		#
		if self[:input_selected] != self[:target_input]
			if self[:target_input].nil?
				self[:target_input] = self[:input_selected]
			else
				switch_input(self[:target_input]) 
				logger.debug "-- NEC input state may not be correct, desired: #{self[:target_input]} current: #{self[:input_selected]}"
			end
		end
	end
	
	
	
	def process_input_switch(data)
		logger.debug "-- NEC projector responded to switch input command"	

		if data[-2] != 0xFF
			status_input
			return true
		end
		
		logger.debug "-- NEC projector failed to switch input with command: #{byte_to_hex(array_to_str(last_command))}"
		return false
	end
	

	def process_mute_state(data)
		logger.debug "-- NEC projector responded to mute state command"
		
		self[:picture_mute] = data[-17] == 0x01
		self[:audio_mute] = data[-16] == 0x01
		self[:onscreen_mute] = data[-15] == 0x01
		
		#if !self[:onscreen_mute] && self[:lamp_status]
			#
			# Always mute onscreen
			#
		#	mute_onscreen
		#end
		
		self[:mute] = self[:picture_mute] && self[:audio_mute]
	end

	
	#
	# For commands that require a checksum (volume, zoom)
	#
	def send_checksum(command, options = {})
		#
		# Prepare command for sending
		#
		command = str_to_array(hex_to_byte(command)) unless command.class == Array
		check = 0
		command.each do |byte|	# Loop through the first to second last element
			check = (check + byte) & 0xFF
		end
		command << check
		send(command, options)
	end
	
	def check_checksum(data)
		check = 0
		data[0..-2].each do |byte|	# Loop through the first to second last element
			check = (check + byte) & 0xFF
		end
		return check == data[-1]	# Check the check sum equals the last element
	end
end
