
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
# mute (picture, audio and onscreen)
# picture_mute
# audio_mute
# onscreen_mute
# picture_freeze
# 
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
		logger.debug 'connected to NEC projector...'
		send(COMMAND[:status_state], :hex_string => true)
	end

	def disconnected
		logger.debug 'disconnected NEC from projector...'
	end
	

	#
	# Volume Modification
	#
	def volume_up
		
	end
	
	def volume_down
		
	end
	
	def volume(vol)
		#					 D1  D2 .. D5 + CKS
		"03H 10H 00H 00H 05H 05H 00H" # volume base command
		# D3 = 00 (absolute vol) or 01 (relative vol)
		# D4 = value (lower bits 0 to 63)
		# D5 = value (higher bits always 00h)
				
		
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
		:freeze_picture => "$01,$98,$00,$00,$01,$01,$9B",
		:unfreeze_picture => "$01,$98,$00,$00,$01,$02,$9C",
		
		# Input Selection
		:input_component1 =>"$02,$03,$00,$00,$02,$01,$10,$18",
		:input_component2 =>"$02,$03,$00,$00,$02,$01,$11,$19",
		:input_dvi =>		"$02,$03,$00,$00,$02,$01,$1A,$22",
		:input_dvi_d =>		"$02,$03,$00,$00,$02,$01,$02,$0A",
		:input_lan =>		"$02,$03,$00,$00,$02,$01,$20,$28",
		:input_vga =>		"$02,$03,$00,$00,$02,$01,$01,$09",
		:input_rgbhv =>		"$02,$03,$00,$00,$02,$01,$02,$0A",
		:input_svideo1 =>	"$02,$03,$00,$00,$02,$01,$0B,$13",
		:input_svideo2 =>	"$02,$03,$00,$00,$02,$01,$0C,$14",
		:input_viewer =>	"$02,$03,$00,$00,$02,$01,$1F,$27",
		
		:status_model =>	"00H 85H 00H 00H 01H 04H 8A",	# request model name (both of these are related)
		:status_mute =>		"00H 85H 00H 00H 01H 03H 89H",	# MUTE STATUS REQUEST (Check 10H on byte 5)
		:status_power =>	"00H 81H 00H 00H 00H 81H",		# Running sense (ret 81)
		:status_state =>	"00H C0H 00H 00H 00H C0H",		# Common data request (ret C0)
		:status_error =>	"00H 88H 00H 00H 00H 88H",		# ERROR STATUS REQUEST (ret 88)
		:status_lamp =>		"0x03 8CH 00H 00H 00H 8FH",		# LAMP INFORMATION REQUEST
		
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
		if [0xA0, 0xA1, 0xA2, 0xA3].include?(data[0])
			logger.warn "-- NEC projector, sent fail code for response :#{byte_to_hex(array_to_str(data))}"
			return false
		end	

		#
		# Process a successful command
		#
		case data[1]
			when 0x00, 0x01
				logger.debug "-- NEC projector sent power command response"
				return process_power_command(data)
			when 0x81
				logger.debug "-- NEC projector sent power status command response"
				return process_power_status(data)
			when 0xC0
				logger.debug "-- NEC projector sent working state command response"
				process_working_state(data)
				return true
		end
		
		logger.info "-- NEC projector, no status updates defined for response :#{byte_to_hex(array_to_str(data))}"
		return true	# to prevent retries on commands we were not expecting
	end
	
	
	private
	

	def process_power_command(data)
		last = last_command
		
		#
		# Ensure a change of power state was the last command sent
		#
		if last[1] == 0x00 || last[1] == 0x01
			if data[1] == 0x00
				self[:lamp_target] = On
			else
				self[:lamp_target] = Off
			end
			
			send(COMMAND[:status_power], :hex_string => true)	# Queues the status power command
		end
		
		return true												# Command success
	end
	
	def process_power_status(data)
		return false unless data[0] == 0x20 && check_checksum(data)	# Check command was a success
		
		self[:lamp_status] = (data[5] & 0x02) > 0x0	# Power on?

		if (data[5] & 0x20) > 0 || (data[5] & 0x80) > 0
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
			send(COMMAND[:status_power], :hex_string => true)	# Then re-queue this command			

		elsif (data[5] & 0x40) > 0	# Selecting signal processing
			sleep(1)
			send(COMMAND[:status_power], :hex_string => true)	# Then re-queue this command
		else
			#
			# We are in a stable state!
			#
			if self[:lamp_status] != self[:lamp_target]
				sleep(3)
				if self[:lamp_target] == On
					send(COMMAND[:lamp_on], :hex_string => true)
				elsif self[:lamp_target] == Off
					send(COMMAND[:lamp_off], :hex_string => true)
				end
				logger.debug "NEC projector in an undesirable power state... (Correcting)"
			else
				logger.debug "NEC projector is in a good power state..."
			end
		end
		
		return true
	end
	
	def process_working_state(d)
		data_base = 4 # 4 + 1 = data01 aka manual
		
		# projector type = d05, d74, d75
		#
		
		# status d73
		#	0x00 = lamp off
		#	0x04 = lamp on
		#	0x05 = cooling
		#	0x06 = error
		#	else internal during a state transition
		#
		#
		# forced_onscreen_muted d70 (0x00 off, 0x01 on)
		# onscreen muted d87 (0x00 off, 0x01 on)
		# onscreen displaying d71 (0x00 not on, 0x01 displaying)
		#
		# changing source d72 (0x00 steady image, 0x01 processing signal)
		# display contents d89
		#	0x00 = picture displaying
		#	0x01 = no signal
		#	0x02 = viewer
		#	0x03 = test pattern
		#	0x04 = lan displaying
		# 
		
		# lamp status = d08 (0x00 off, 0x01 on)
		# cooling? d09 = (0x00 no, 0x01 yes)
		self[:lamp_target] = d[8] == 0x01
		self[:lamp_status] = self[:lamp_target]
		self[:lamp_cooling] = d[9] == 0x01
		
		# input selected: d11 == port number, d12 == port type (vga, dvi, ect)
		# picture mute d33 = (0x00 off, 0x01 on)
		# audio mute d34 = (0x00 off, 0x01 on)
		#self[:]
	end
	
	#
	# For commands that require a checksum (volume, zoom)
	#
	def send_checksum(command, options = {})
		#
		# Prepare command for sending
		#
		command = str_to_array(hex_to_byte(command))
		check = 0
		data.each do |byte|	# Loop through the first to second last element
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
