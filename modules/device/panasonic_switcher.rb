# :title:Panasonic video switcher
#
# => Control port:	60030			(fixed)
# => IP:			192.168.0.8		(Default)
# => Subnet:		255.255.255.0	(Default)
#
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# num_inputs
# num_outputs
#
# output_1 => input
# output_2
# output_3
#

class PanasonicSwitcher < Control::Device
	DelayTime = 1.0 / 24.0	# Time of 1 video frame to process
	

	def on_load
		#
		# Setup constants
		#
	end
	
	def connected
		#
		# Get current state of the switcher
		#
		do_poll
	
		@polling_timer = periodic_timer(30) do		# Check every 30 seconds for changes
			logger.debug "-- Polling Switcher"
			do_poll
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
	end
	
	def response_delimiter
		0x03	# Used to interpret the end of a message (this is why data values are encoded as ASCII)
	end


	Commands = {
		:set_bus => 	"SBUS",
		:request_bus => "QBST"
	}
	
	ControlBus = {
		:a_bus => 	"00",
		:b_bus => 	"01",
		:pgm => 	"02",
		:pvw => 	"03",
		:key_f => 	"04",
		:key_s => 	"05",
		:p_in_p => 	"10",
		:aux => 	"12"
	}
	
	CrossPoint = {
		:xpt_1 =>	"00",
		:xpt_2 =>	"01",
		:xpt_3 =>	"02",
		:xpt_4 =>	"03",
		:xpt_5 =>	"04",
		:xpt_6 =>	"05",
		:xpt_7 =>	"06",
		:xpt_8 =>	"07",
		:xpt_9 =>	"08",
		:xpt_10 =>	"09",
		:input_1 => "50",
		:input_2 => "51",
		:input_3 => "52",
		:input_4 => "53",
		:input_5 => "54",
		:sdi_1_in => "50",
		:sdi_2_in => "51",
		:sdi_3_in => "52",
		:sdi_4_in => "53",
		:dvi_in => "54",
		:colour_bar	=> "70",
		:colour_background	=> "71",
		:frame_mem_1 => "73",
		:frame_mem_2 => "74",
		:pgm	=> "77",
		:pvw	=> "78",
		:keyout	=> "79",
		:cln	=> "80"
	}
	

	def switch(map)
		#
		# Need more information on how the device works
		# 	the usage I'm thinking of is: switch({:a_bus => :sdi_1_in, :b_bus => :dvi_in})
		#
		map.each do |output, input|
			do_send(Commands[:set_bus] + ":#{output}:#{input}", {:wait => false, :delay => DelayTime})
			do_send(Commands[:request_bus] + ":#{output}")
		end
	end
	
	
	
	#
	# Response callback
	#
	def received(data)
		data.shift(6)		# removes the leading character + 4 byte command string + :
		data = array_to_str(data).split(':')
		
		#
		# data[0] == bus reference
		# data[1] == xpt1-9 or 99 (not assigned)
		# data[3] == Tally status (this may not be sent depending on the bus?)
		#
		
		return true	# Response was valid
	end
	
	
	private
	
	
	def do_poll
		#
		# TODO:: Get the status of all the ports (low priority)
		#
	end
	
	def do_send(command, options = {})
		send("" << 0x02 << command << 0x03, options)
	end
end