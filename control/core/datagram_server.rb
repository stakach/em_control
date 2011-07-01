
module Control

	$datagramServer = nil

	class DatagramBase
		include Utilities
		include DeviceConnection
		
		def do_send_data(data)
			$datagramServer.do_send_data(DeviceModule.lookup[@parent], data)
		end
	end

	module DatagramServer
		def initialize *args
			super
			
			if !$datagramServer.nil?
				return
			end
			
			$datagramServer = self
			@devices = {}
			
			EM.defer do
				System.logger.info 'running datagram server on an ephemeral port'
			end
		end


		#
		# Eventmachine callbacks
		#
		def receive_data(data)
			#
			# TODO:: IPv6 peername support
			#	Use wikipedia to compare the formats
			#	Differenciate by inspecting the size
			#
			ip = get_peername[2,6].unpack "nC4"
			begin
				@devices["#{ip[1..-1].join(".")}:#{ip[0]}"].do_receive_data(data)
			rescue
				#
				# TODO:: error messages here if device is null ect
				#
			end
		end
		

		#
		# Additional controls
		#	TODO:: add debug information
		#
		def do_send_data(scheme, data)
			send_datagram(data, scheme.ip, scheme.port)
		end

		def add_device(scheme, device)
			EM.schedule do
				@devices["#{scheme.ip}:#{scheme.port}"] = device
			end
		end
		
		def remove_device(scheme)
			EM.schedule do
				@devices.delete("#{scheme.ip}:#{scheme.port}")
			end
		end
	end
end
