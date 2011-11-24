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

class PanasonicHs50e < Control::Device
	DelayTime = 1.0 / 25.0	# Time of 1 video frame to process == 24.0
	

	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:delay => DelayTime			# minimum delay between sends
		}
	end
	
	def connected
		#
		# Get current state of the switcher
		#
		do_poll
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#
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
		:sdi_1_in => "50",
		:sdi_2_in => "51",
		:sdi_3_in => "52",
		:sdi_4_in => "53",
		:dvi_in => "54",
		:input_1 => "50",
		:input_2 => "51",
		:input_3 => "52",
		:input_4 => "53",
		:input_5 => "54",
		:colour_bar	=> "70",
		:colour_background	=> "71",
		:black => "72",
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
		# 	the usage I'm thinking of is: switch({:sdi_1_in => :a_bus, :dvi_in => :b_bus})
		#
		map.each do |input, output|
			input = input.to_sym if input.class == String
			output = output.to_sym if output.class == String
			
			do_send(Commands[:set_bus] + ":#{ControlBus[output]}:#{CrossPoint[input]}", {:wait => false})
			do_send(Commands[:request_bus] + ":#{ControlBus[output]}")
		end
	end
	
	
	
	#
	# Response callback
	#
	def received(data, command)
		#
		# removes the leading character and ensures we only have the start of this message
		#
		data = data.split("" << 0x02)[-1]


		logger.debug "HS50E sent #{data}"

		
		
		#
		# removes the 4 byte command string and the leading ':' character
		#
		data = data[5..-1].split(':')
		
		#
		# data[0] == bus reference
		# data[1] == xpt1-9 or 99 (not assigned)
		# data[2] == Tally status (this may not be sent depending on the bus?)
		#
		
		output = ControlBus.invert[data[0]]
		self[output] = CrossPoint.invert[data[1]]
		self["#{output}_tally"] = data[2] == '1'
		
		return true	# Response was valid
	end
	
	
	private
	
	
	#
	# Get the status of all the ports (low priority)
	#
	def do_poll
		do_send(Commands[:request_bus] + ":#{ControlBus[:a_bus]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:b_bus]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:pgm]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:pvw]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:key_f]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:key_s]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:p_in_p]}", :priority => 99)
		do_send(Commands[:request_bus] + ":#{ControlBus[:aux]}", :priority => 99)
	end
	
	def do_send(command, options = {})
		send("" << 0x02 << command << 0x03, options)
	end
end