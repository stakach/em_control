
require 'json'

class PodInterface < Control::Logic		
	module AMXInterface
		def post_init
			begin
				#
				# Someone connected -- check they are valid
				#
				port, ip = Socket.unpack_sockaddr_in(get_peername)
				Control::System.logger.info "AMX POD Interface -- connection from: #{ip}"
			rescue => e
				Control.print_error(Control::System.logger, e, {
					:message => "module PodInterface error starting connection",
					:level => Logger::ERROR
				})
			end
		end
	
		def receive_data(data)
			begin
				(@buffer ||= BufferedTokenizer.new('' << 0x03)).extract(data).each do |line|
					line = line.split("" << 0x02)
					if line.length >= 2
						
						process_command(line[-1])
						
					end
				end
			rescue => e
				EM.defer do
					Control.print_error(Control::System.logger, e, {
						:message => "module PodInterface error extracting data",
						:level => Logger::ERROR
					})
				end
			end
		end
		
		protected
		
		def process_command(line)
			EM.defer do
				begin
					line = JSON.parse(line, {:symbolize_names => true})
					
					#
					# Process commands here
					#
					systems = Zone.where(:name => line[:control]).first.control_systems
					failed = false
					
					if not line[:presentation].nil?
						systems.each do |pod|
							Control::System[pod.name][:Pod].enable_sharing(line[:presentation])
						end
					elsif not line[:override].nil?
						systems.each do |pod|
							Control::System[pod.name][:Pod].do_share(line[:override])
						end
					else
						failed = true
						send_data("" << 0x02 << JSON.generate({'result' => false}) << 0x03)
					end
					
					send_data("" << 0x02 << JSON.generate({'result' => true}) << 0x03) unless failed
					
					ActiveRecord::Base.clear_active_connections!
				rescue => e
					Control.print_error(Control::System.logger, e, {
						:message => "module PodInterface error processing AMX command",
						:level => Logger::ERROR
					})
				end
			end
		end
	end

	def on_load
		@server = EventMachine::start_server '0.0.0.0', 24842, AMXInterface
		logger.info "AMX POD Interface started"
	end
	
	
	def on_unload
		EventMachine::stop_server(@server) unless @server.nil?
		logger.info "AMX POD Interface stopped"
	end
	
	
	def on_update
		EventMachine::stop_server(@server) unless @server.nil?
		@server = EventMachine::start_server '0.0.0.0', 24842, AMXInterface
		logger.info "AMX POD Interface reloaded"
	end
end
