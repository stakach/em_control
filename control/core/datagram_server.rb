
module Control

	$datagramServer = nil

	class DatagramBase
		include Utilities
		include DeviceConnection
		
		def do_send_data(data)
			$datagramServer.do_send_data(DeviceModule.lookup(@parent), data)
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
			@ips = {}
			
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
		#
		def do_send_data(scheme, data)
			begin
				#
				# Just in case the address is a domain name we want to ensure the
				#	IP lookups are always correct and we are always sending to the
				#	specified device
				#
				#
				# TODO:: https://github.com/eventmachine/eventmachine/blob/master/tests/test_resolver.rb
				# => Use the non-blocking resolver in the future
				#
				ip = Addrinfo.udp(scheme.ip, 80).ip_address
				text = "#{scheme.ip}:#{scheme.port}"
				old_ip = @ips[text]
				if old_ip != ip
					EM.schedule do	# All modifications are on the reactor thread instead of locking
						device = @devices.delete("#{old_ip}:#{scheme.port}")
						@ips[text] = ip
						@devices["#{ip}:#{scheme.port}"] = device
					end
				end
				send_datagram(data, ip, scheme.port)
			rescue => e
				EM.defer do
					System.logger.info e.message + " calling UDP send for #{scheme.dependency.actual_name} @ #{scheme.ip} in #{scheme.control_system.name}"
				end
			end
		end

		def add_device(scheme, device)
			EM.schedule do
				begin
					#
					# TODO:: https://github.com/eventmachine/eventmachine/blob/master/tests/test_resolver.rb
					# => Use the non-blocking resolver in the future
					#
					ip = Addrinfo.udp(scheme.ip, 80).ip_address
					@devices["#{ip}:#{scheme.port}"] = device
					@ips["#{scheme.ip}:#{scheme.port}"] = ip
				rescue => e
					@devices["#{scheme.ip}:#{scheme.port}"] = device
					@ips["#{scheme.ip}:#{scheme.port}"] = scheme.ip
					
					EM.defer do
						System.logger.info e.message + " adding UDP #{scheme.dependency.actual_name} @ #{scheme.ip} in #{scheme.control_system.name}"
					end
				end
			end
		end
		
		def remove_device(scheme)
			EM.schedule do
				begin
					ip = @ips.delete("#{scheme.ip}:#{scheme.port}")
					@devices.delete("#{ip}:#{scheme.port}")
				rescue
					EM.defer do
						System.logger.info e.message + " removing UDP #{scheme.dependency.actual_name} @ #{scheme.ip} in #{scheme.control_system.name}"
					end
				end
			end
		end
	end
end
