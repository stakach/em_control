module Control
	class Modules
		@@modules = {}	# modules (dependency_id => module class)
		@@load_lock = Mutex.new
		@@loading = nil
	
		def self.[] (module_id)
			@@modules[module_id]
		end
	
		def self.load_lock
			@@load_lock
		end
	
		def self.loading
			@@loading
		end
	
		def self.loading=(mod)
			@@loading = mod
		end
	
		def self.load_module(dep)
			begin
				if File.exists?(ROOT_DIR + '/modules/device/' + dep.filename)
					load ROOT_DIR + '/modules/device/' + dep.filename
				else
					load ROOT_DIR + '/modules/logic/' + dep.filename
				end
				@@modules[dep.id] = dep.classname.classify.constantize
			rescue => e
				#
				# TODO:: Log file not found
				#
			end
		end
	end


	class DeviceModule
		@@instances = {}	# id => instance
		@@devices = {}	# ip:port => instance
		@@lookup = {}	# instance => DB Record


		def initialize(schemeDevice)
			if @@instances[schemeDevice.id].nil?
				if @@devices["#{schemeDevice.ip}:#{schemeDevice.port}"].nil?
					@@instances[schemeDevice.id] = schemeDevice
					@@devices["#{schemeDevice.ip}:#{schemeDevice.port}"] = schemeDevice
					instantiate_module(schemeDevice)
				else
					@@instances[schemeDevice.id] = @@devices["#{schemeDevice.ip}:#{schemeDevice.port}"]
				end
			else
				#
				# Perform in place update
				#	Check dependency id too
				#
				# check differences (if any then create a new instance for "ip:port" and id)
			end
		end
	

		def self.lookup
			@@lookup
		end
	

		attr_reader :instance

	
		protected
	
	
		def instantiate_module(schemeDevice)
			if Modules[schemeDevice.dependency.id].nil?
				Modules.load_module(schemeDevice.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end
			@instance = Modules[schemeDevice.dependency.id].new(System.schemes[schemeDevice.scheme_id])
			@@lookup[@instance] = schemeDevice
			Modules.load_lock.synchronize {		# TODO::dangerous (locking on reactor thread)
				Modules.loading = @instance
				if !schemeDevice.udp
					EM.connect schemeDevice.ip, schemeDevice.port, Device::Base
				else
					#
					# Load UDP device here
					#	Create UDP base
					#	Add device to server
					#	Call connected
					#
					devBase = DatagramBase.new
					$datagramServer.add_device(schemeDevice, devBase)
					EM.defer do
						devBase.call_connected
					end
				end
			}
		end
	end


	class LogicModule
		@@instances = {}	# id => module instance


		def initialize(schemeDevice)
			if @@instances[schemeDevice.id].nil?
				@@instances[schemeDevice.id] = self
				instantiate_module(schemeDevice)
			else
				#
				# Perform in place update
				#	Check dependency id too
				#
				# check differences (if any then create a new instance for "ip:port" and id)
			end
		end


		protected


		def instantiate_module(schemeDevice)
			if Modules[schemeDevice.dependency.id].nil?
				Modules.load_module(schemeDevice.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end
			@instance = Modules[schemeDevice.dependency.id].new(System.schemes[schemeDevice.scheme_id])
		end
	end
end