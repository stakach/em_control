
#
# Will reside in user defined file
#
class AllNec < Control::Device
	

	def connected
		p 'connected to projector...'
		send(COMMAND[:status_state], :hex_string => true)
	end

	def disconnected
		p 'disconnected from projector...'
	end
	

	#
	# Automatically creates a callable function for each command
	#
	def method_missing(m, *args, &block)
		if !COMMAND[m].nil?
			send(COMMAND[m], :hex_string => true)
		else
			raise "invalid command"
		end
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
		:mute_sound =>		"02H 12H 00H 00H 00H 14H",
		:unmute_sound =>	"02H 13H 00H 00H 00H 15H",
		:mute_onscreen =>	"02H 14H 00H 00H 00H 16H",
		:unmute_onscreen =>	"02H 15H 00H 00H 00H 17H",
		
		# Input Selection
		:input_component1 =>"$02,$03,$00,$00,$02,$01,$10,$18",
		:input_component2 =>"$02,$03,$00,$00,$02,$01,$11,$19",
		:input_dvi_a =>		"$02,$03,$00,$00,$02,$01,$1A,$22",
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

	# Return true if command success, nil if still waiting, false if fail
	def received(data)
		case data[1]
			when 0x00, 0x01
				p "-- proj sent power command"
				return process_power_command(data)
			when 0x81
				p "-- proj sent power status command"
				return process_power_status(data)
			when 0xC0
				p "-- proj sent working state command"
		end
		
		p "-- proj sent unknown response"
		return true	# to prevent retries on commands we were not expecting
	end
	
	
	private
	

	def process_power_command(data)
		last = last_command
		if last[1] == 0x00 || last[1] == 0x01
			if data[1] == 0x00
				self[:power_target] = On
			else
				self[:power_target] = Off
			end
			
			send(COMMAND[:status_power], :hex_string => true)	# Queues the status power command
		end
		
		return true												# Command success
	end
	
	def process_power_status(data)
		return false unless data[0] == 0x20 && check_checksum(data)	# Check command was a success
		
		self[:power] = (data[5] & 0x02) > 0x0	# Power on?

		if (data[5] & 0x20) > 0 || (data[5] & 0x80) > 0
			# Projector cooling || power on off processing
			
			if self[:power_target] == On
				self[:lamp_cooling] = false
				self[:lamp_warming] = true
	
				p "lamp warming..."
						
	
			elsif self[:power_target] == Off
				self[:lamp_warming] = false
				self[:lamp_cooling] = true
				
				p "lamp cooling..."
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
			if self[:power] != self[:power_target]
				if self[:power_target] == On
					send(COMMAND[:lamp_on], :hex_string => true)
				elsif self[:power_target] == Off
					send(COMMAND[:lamp_off], :hex_string => true)
				end
				p "Projector in bad state..."
			else
				p "Projector in good state..."
			end
		end
		
		return true
	end
	
	#
	# For commands that require a checksum
	#
	def send_checksum(command, options = {})
	end
	
	def check_checksum(data)
		check = 0
		data[0..-2].each do |byte|	# Loop through the first to second last element
			check = (check + byte) & 0xFF
		end
		return check == data[-1]	# Check the check sum equals the last element
	end
end
