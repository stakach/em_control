module Control

	$theUdpServer = nil

	class UdpBase
		include Utilities
		include DeviceConnection
		
		def do_send_data(data)
			$theUdpServer.do_send_data(DeviceModule.lookup[@parent], data)
		end
	end

	module UdpServer
		def initialize *args
			super
			
			$theUdpServer = self
			@data_lock = Mutex.new
			@devices = {}
			
			EM.defer do
				System.logger.info 'running UDP server on an ephemeral port'
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
				@data_lock.synchronize {
					@devices["#{ip[1..-1].join(".")}:#{ip[0]}"].receive_data(data)
				}
			rescue
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
			@data_lock.synchronize {
				@devices["#{scheme.ip}:#{scheme.port}"] = device
			}
		end
		
		def remove_device(scheme)
			@data_lock.synchronize {
				@devices.delete("#{scheme.ip}:#{scheme.port}")
			}
		end
	end

end