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


		def initialize(controllerDevice)
			if @@instances[controllerDevice.id].nil?
				if @@devices["#{controllerDevice.ip}:#{controllerDevice.port}"].nil?
					@@instances[controllerDevice.id] = controllerDevice
					@@devices["#{controllerDevice.ip}:#{controllerDevice.port}"] = controllerDevice
					instantiate_module(controllerDevice)
				else
					@@instances[controllerDevice.id] = @@devices["#{controllerDevice.ip}:#{controllerDevice.port}"]
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
	
	
		def instantiate_module(controllerDevice)
			if Modules[controllerDevice.dependency.id].nil?
				Modules.load_module(controllerDevice.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end
			@instance = Modules[controllerDevice.dependency.id].new(System.controllers[controllerDevice.controller_id])
			@@lookup[@instance] = controllerDevice
			Modules.load_lock.synchronize {		# TODO::dangerous (locking on reactor thread)
				Modules.loading = @instance
				if !controllerDevice.udp
					EM.connect controllerDevice.ip, controllerDevice.port, Device::Base
				else
					#
					# Load UDP device here
					#	Create UDP base
					#	Add device to server
					#	Call connected
					#
					devBase = DatagramBase.new
					$datagramServer.add_device(controllerDevice, devBase)
					EM.defer do
						devBase.call_connected
					end
				end
			}
		end
	end


	class LogicModule
		@@instances = {}	# id => module instance
		@@lookup = {}	# instance => DB Record


		def initialize(controllerLogic)
			if @@instances[controllerLogic.id].nil?
				@@instances[controllerLogic.id] = self
				instantiate_module(controllerLogic)
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


		protected


		def instantiate_module(controllerLogic)
			if Modules[controllerLogic.dependency.id].nil?
				Modules.load_module(controllerLogic.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end
			@instance = Modules[controllerLogic.dependency.id].new(System.controllers[controllerLogic.controller_id])
			@@lookup[@instance] = controllerLogic
		end
	end
end