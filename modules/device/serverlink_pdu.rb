# :title:Serverlink SLP-S1608-H
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# request_id
#
# outlet_a
# outlet_b
# outlet_c
# outlet_d
# outlet_e
# outlet_f
# outlet_g
# outlet_h
#


class ServerlinkPdu < Control::Device

	#
	# Sets up any constants 
	#
	def on_load
		
		#
		# Setup constants
		#
		self[:request_id] = 0
		self[:status_string] = "1,1,1,1,1,1,1,1"
		self[:target_string] = nil
		
		@sync_lock = Mutex.new
	end

	def connected
		#
		# Get current state of the PDU
		#
		get_status
	end
	
	def get_status
		next_request

		command = [0x30,0x2F,0x02,0x01,0x00,0x04, 0x06, 0x70,
				0x75,0x62,0x6C,0x69,0x63, 0xA0 ,0x22,0x02,0x04,
				0x00,0x00,0x00,self[:request_id],	# Request ID
				0x02,0x01,0x00,0x02,0x01,0x00,0x30,0x14,0x30,0x12,
				0x06,0x0E,0x2B,0x06,0x01,0x04,0x01,0x81,0x88,0x0C,
				0x01,0x02,0x09,0x01,0x0D,0x00,0x05,0x00]
		
		logger.debug "-- Serverlink PDU status command sent"
				
		send(command)
	end
	
	OUTLETS = {
		:outlet_a => 0,
		:outlet_b => 2,
		:outlet_c => 4,
		:outlet_d => 6,
		:outlet_e => 8,
		:outlet_f => 10,
		:outlet_g => 12,
		:outlet_h => 14
	}
	def set_outlets(outlet)
		next_request

		command = [0x30,0x3E,0x02,0x01,0x00,0x04,0x06,0x70,0x75,0x62,
				0x6C,0x69,0x63,0xA3,0x31,0x02,0x04,
				0x00,0x00,0x00,self[:request_id],	# Request ID
				0x02,0x01,0x00,0x02,0x01,0x00,0x30,0x23,0x30,0x21,0x06,
				0x0E,0x2B,0x06,0x01,0x04,0x01,0x81,0x88,0x0C,0x01,0x02,
				0x09,0x01,0x0D,0x00,0x04,0x0F]
		
		
		@sync_lock.synchronize {
			string = self[:target_string]
			string = self[:status_string] if string.nil?

			outlet.each do |id, value|	# Value == true or false, id == :outlet_a
				index = OUTLETS[id]
				if !index.nil?
					string[index] = value ? "1" : "0"
				end
			end
		
			logger.debug "-- Serverlink PDU set command sent"
		
			self[:target_string] = string
		}
		send(array_to_str(command) + string)
	end
	
	def received(data)
		string = array_to_str(data[-15..-1])
		self[:status_string] = string
		
		logger.info "-- Serverlink PDU, sent status update: 0x#{string}"
		
		OUTLETS.each do |id, value|
			self[id] = string[value] == "1" ? true : false
		end
		
		if(string != self[:target_string])
			return false
		end
		return true
	end
	
	
	private
	

	def next_request
		self[:request_id] = (self[:request_id] + 1) & 0xFF
	end

end

