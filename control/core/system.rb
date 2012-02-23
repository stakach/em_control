module Control
	class System

		@@systems = {:'---GOD---' => self}		# system_name => system instance
		@@controllers = {}						# controller_id => system instance
		@@logger = nil
		@@communicator = Control::Communicator.new(self)
		@@communicator.start(true)
		@@god_lock = Mutex.new
		
		
		def self.new_system(controller, log_level = Logger::INFO)
			controller = ControlSystem.find(controller) if controller.class == Fixnum
			controller = ControlSystem.where('name = ?', controller).first if controller.class == String
			
			begin
				@@god_lock.lock
				if @@controllers[controller.id].nil?
					@@god_lock.unlock
					System.new(controller, log_level)
				else
					@@god_lock.unlock
				end
			rescue => e
				begin
					@@god_lock.unlock
				rescue
				end
				
				Control.print_error(@@logger, e, {
					:message => "class System in self.new_system",
					:level => Logger::ERROR
				})
			end
		end
		
		
		#
		# Reloads a dependency live
		#	This is the re-load code function (live bug fixing - removing functions does not work)
		#
		def self.reload(dep)
			System.logger.info "reloading dependency: #{dep}"
			
			dep = Dependency.find(dep)
			Modules.load_module(dep)
			
			updated = {}
			dep.devices.select('id').each do |dev|
				begin
					inst = DeviceModule.instance_of(dev.id)
					inst.on_update if (!!!updated[inst]) && inst.respond_to?(:on_update)
				ensure
					updated[inst] = true
				end
			end
			
			updated = {}
			dep.logics.select('id').each do |log|
				begin
					inst = LogicModule.instance_of(log.id)
					inst.on_update if (!!!updated[inst]) && inst.respond_to?(:on_update)
				ensure
					updated[inst] = true
				end
			end
		end
		
		#
		# Allows for system updates on the fly
		#	Dangerous (Could be used to add on the fly interfaces)
		#
		def self.force_load_file(path)
			load ROOT_DIR + path
		end
		
		
		#
		# System Logger
		#	
		def self.logger
			@@logger
		end
		
		def self.logger=(log)
			@@logger = log
		end
		
		#def self.controllers
		#	@@controllers
		#end
	
		#def self.systems
		#	@@systems
		#end
		
		def self.communicator
			@@communicator
		end
		
		def self.[] (system)
			system = system.to_sym if system.class == String
			@@god_lock.synchronize {
				@@systems[system]
			}
		end
		
		
		
		#
		# For access via communicator as a super user
		#
		def self.modules
			self
		end
		def self.instance
			self
		end
		def instance
			self
		end
		# ---------------------------------
		
		
	
		#
		#	Module accessor
		#
		def [] (mod)
			mod = mod.to_sym if mod.class == String
			@modules[mod].instance
		end

		attr_reader :modules
		attr_reader :communicator
		attr_reader :controller
		attr_accessor :logger
		
		
		
		#
		# Starts the control system if not running
		#
		def start(force = false)
			System.logger.info "starting #{@controller.name}"
			@sys_lock.synchronize {
				@@god_lock.synchronize {
					@@systems.delete(@controller.name.to_sym)
					@controller.reload(:lock => true)
					@@systems[@controller.name.to_sym] = self
				}
				
				if !@controller.active || force
					
					if @logger.nil?
						if Rails.env.production?
							@logger = Logger.new("#{ROOT_DIR}/interface/log/system_#{@controller.id}.log", 10, 4194304)
						else
							@logger = Logger.new(STDOUT)
						end
						@logger.formatter = proc { |severity, datetime, progname, msg|
							"#{datetime.strftime("%d/%m/%Y @ %I:%M%p")} #{severity}: #{@controller.name} - #{msg}\n"
						}
					end
					
					@controller.devices.includes(:dependency).each do |device|
						load_hooks(device, DeviceModule.new(self, device))
					end
					
					@controller.services.includes(:dependency).each do |service|
						load_hooks(service, ServiceModule.new(self, service))
					end
				
					@controller.logics.includes(:dependency).each do |logic|
						load_hooks(logic, LogicModule.new(self, logic))
					end
				end
				
				@controller.active = true
				@controller.save
				
				@communicator.start
			}
		end
		
		#
		# Stops the current control system
		# 	Loops through the module instances.
		#
		def stop
			System.logger.info "stopping #{@controller.name}"
			@sys_lock.synchronize {
				stop_nolock
			}
		end
		
		#
		# Unload and then destroy self
		#
		def delete
			System.logger.info "deleting #{@controller.name}"
			@sys_lock.synchronize {
				stop_nolock
				
				@@god_lock.synchronize {
					@@systems.delete(@controller.name.to_sym)
					@@controllers.delete(@controller.id)
				}
				
				begin
					@controller.destroy!
				rescue
					# Controller may already be deleted
				end
				@modules = nil
			}
		end
		
		
		#
		# Log level changing on the fly
		#
		def log_level(level)
			@sys_lock.synchronize {
				@log_level = Control::get_log_level(level)
				if @controller.active
					@logger.level = @log_level
				end
			}
		end
		
	
		protected
		
		
		def stop_nolock
			
			begin
				@@god_lock.synchronize {
					@@systems.delete(@controller.name.to_sym)
					@controller.reload(:lock => true)
					@@systems[@controller.name.to_sym] = self
				}
			rescue
				# Assume controller may have been deleted
			end
			
			if @controller.active
				@communicator.shutdown
				modules_unloaded = {}
				@modules.each_value do |mod|
					
					if modules_unloaded[mod] == nil
						modules_unloaded[mod] = :unloaded
						mod.unload
					end
					
				end
				@modules = {}	# Modules no longer referenced. Cleanup time!
				@logger.close if Rails.env.production?
				@logger = nil
			end
			
			@controller.active = false
			begin
				@controller.save
			rescue
				# Assume controller may have been deleted
			end
		end
	
	
		def load_hooks(device, mod)
			module_name = device.dependency.module_name
			count = 2	# 2 is correct
			
			#
			# Loads the modules and auto-names them (display_1, display_2)
			#	The first module of a type has two names (display and display_1 for example)
			#	Load order is controlled by the control_system model based on the ordinal
			#
			if not @modules[module_name.to_sym].nil?
				while @modules["#{module_name}_#{count}".to_sym].present?
					count += 1
				end
				module_name = "#{module_name}_#{count}"
			else
				@modules["#{module_name}_1".to_sym] = mod
			end
			@modules[module_name.to_sym] = mod
			
			#
			# Allow for system specific custom names
			#
			if !device.custom_name.nil?
				@modules[device.custom_name.to_sym] = mod
			end
		end
		
		
		def initialize(controller, log_level)
			
			
			@modules = {}	# controller modules	:name => module instance (device or logic)
			@communicator = Control::Communicator.new(self)
			@log_level = log_level
			@controller = controller
			@sys_lock = Mutex.new
			
			
			#
			# Setup the systems links
			#
			@@systems[@controller.name.to_sym] = self
			@@god_lock.synchronize {
				@@controllers[@controller.id] = self
			}
			
			if @controller.active
				start(true)			# as this is loading the first time we ignore controller active
			end
		end
	end
end