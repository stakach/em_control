require 'socket'

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
			#ip = get_peername[2,6].unpack "nC4"
			port, ip = Socket.unpack_sockaddr_in(get_peername)
			begin
				@devices["#{ip}:#{port}"].do_receive_data(data)
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
			res = ResolverJob.new(scheme.ip)
			res.callback {|ip|
				
				#
				# Just in case the address is a domain name we want to ensure the
				#	IP lookups are always correct and we are always sending to the
				#	specified device
				#
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
			}
			res.errback {|error|
				EM.defer do
					System.logger.info e.message + " calling UDP send for #{scheme.dependency.actual_name} @ #{scheme.ip} in #{scheme.control_system.name}"
				end
			}
		end

		def add_device(scheme, device)
			EM.schedule do
				res = ResolverJob.new(scheme.ip)
				res.callback {|ip|
					@devices["#{ip}:#{scheme.port}"] = device
					@ips["#{scheme.ip}:#{scheme.port}"] = ip
				}
				res.errback {|error|
					@devices["#{scheme.ip}:#{scheme.port}"] = device
					@ips["#{scheme.ip}:#{scheme.port}"] = scheme.ip
				}
				
				EM.defer do
					System.logger.info e.message + " adding UDP #{scheme.dependency.actual_name} @ #{scheme.ip} in #{scheme.control_system.name}"
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
