module Control
	class Modules
		@@modules = {}	# modules (dependency_id => module class)
		@@load_lock = Mutex.new
		@@loading = nil
	
		def self.[] (dep_id)
			@@modules[dep_id]
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
		@@instances = {}	# db id => @instance
		@@dbentry = {}		# db id => db instance
		@@devices = {}		# ip:port:udp => @instance
		@@lookup = {}		# @instance => db id array
		@@lookup_lock = Mutex.new
		
		def initialize(system, controllerDevice)
			@@lookup_lock.synchronize {
				if @@instances[controllerDevice.id].nil?
					@system = system
					@device = controllerDevice.id
					@@dbentry[controllerDevice.id] = controllerDevice
					instantiate_module(controllerDevice)
				end
			}
		end
		
		
		def unload	# should never be called on the reactor thread so no need to defer
			
			@instance.base.shutdown(@system)
			@@lookup_lock.synchronize {
				db = @@lookup[@instance].delete(@device)
				@@instances.delete(db)
				db = @@dbentry.delete(db)
				dev = "#{db.ip}:#{db.port}:#{db.udp}"
				
				if @@lookup[@instance].empty?
					@@lookup.delete(@instance)
					if db.udp
						$datagramServer.remove_device(db)
					end
					@@devices.delete(dev)
				end
			}
			
		end
		

		def self.lookup(instance)
			@@lookup_lock.synchronize {
				return @@dbentry[@@lookup[instance][0]]
			}
		end
		
		def self.instance_of(db_id)
			@@lookup_lock.synchronize {
				return @@instances[db_id]
			}
		end
		
		
		attr_reader :instance
		
		
		protected
	
	
		def instantiate_module(controllerDevice)
			if Modules[controllerDevice.dependency.id].nil?
				Modules.load_module(controllerDevice.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end			
			
			
			baselookup = "#{controllerDevice.ip}:#{controllerDevice.port}:#{controllerDevice.udp}"
			if @@devices[baselookup].nil?
				
				#
				# Instance of a user module
				#
				@instance = Modules[controllerDevice.dependency_id].new(controllerDevice.tls)
				@instance.join_system(@system)
				@@instances[@device] = @instance
				@@devices[baselookup] = @instance
				@@lookup[@instance] = [@device]
			
				devBase = nil
				Modules.load_lock.synchronize {
					Modules.loading = [@instance, @system]
					
					if !controllerDevice.udp
						begin
							EM.connect Addrinfo.tcp(controllerDevice.ip, 80).ip_address, controllerDevice.port, Device::Base
						rescue => e
							System.logger.info e.message + " connecting to #{controllerDevice.dependency.actual_name} @ #{controllerDevice.ip} in #{controllerDevice.control_system.name}"
							EM.connect "127.0.0.1", 10, Device::Base	# Connect to a nothing port until the device name is found or updated
						end
					else
						#
						# Load UDP device here
						#	Create UDP base
						#	Add device to server
						#	Call connected
						#
						devBase = DatagramBase.new
						$datagramServer.add_device(controllerDevice, devBase)
					end
					
					@@devices[baselookup] = Modules.loading	# set in device_connection
				}
				
				if @instance.respond_to?(:on_load)
					begin
						@instance.on_load
					rescue => e
						System.logger.error "-- device module #{@instance.class} error whilst calling: on_load --"
						System.logger.error e.message
						System.logger.error e.backtrace
					end
				end
				
				if controllerDevice.udp
					EM.defer do
						devBase.call_connected	# UDP is stateless (always connected)
					end
				end
			else
				#
				# add parent may lock at this point!
				#
				@instance = @@devices[baselookup]
				@@lookup[@instance] << @device
				@@instances[@device] = @instance
				EM.defer do
					@instance.join_system(@system)
				end
			end
		end
	end


	class LogicModule
		@@instances = {}	# id => @instance
		@@lookup = {}		# @instance => DB Record
		@@lookup_lock = Mutex.new
		

		def initialize(system, controllerLogic)
			@@lookup_lock.synchronize {
				if @@instances[controllerLogic.id].nil?
					instantiate_module(controllerLogic, system)
				end
			}
			if @instance.respond_to?(:on_load)
				begin
					@instance.on_load
				rescue => e
					System.logger.error "-- logic module #{@instance.class} error whilst calling: on_load --"
					System.logger.error e.message
					System.logger.error e.backtrace
				end
			end
		end
		
		def unload
			if @instance.respond_to?(:on_unload)
				begin
					@instance.on_unload
				rescue => e
					System.logger.error "-- logic module #{@instance.class} error whilst calling: on_unload --"
					System.logger.error e.message
					System.logger.error e.backtrace
				end
			end
			
			@@lookup_lock.synchronize {
				db = @@lookup.delete(@instance)
				@@instances.delete(db.id)
			}
		end
		
		def self.lookup(instance)
			@@lookup_lock.synchronize {
				return @@lookup[instance]
			}
		end
		
		def self.instance_of(db_id)
			@@lookup_lock.synchronize {
				return @@instances[db_id]
			}
		end
		
		attr_reader :instance


		protected


		def instantiate_module(controllerLogic, system)
			if Modules[controllerLogic.dependency_id].nil?
				Modules.load_module(controllerLogic.dependency)		# This is the re-load code function (live bug fixing - removing functions does not work)
			end
			@instance = Modules[controllerLogic.dependency_id].new(system)
			@@instances[controllerLogic.id] = @instance
			@@lookup[@instance] = controllerLogic
		end
	end
end