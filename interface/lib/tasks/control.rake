desc 'Start the control system server'
task :control => :environment do
	require './../em-control.rb'

	loglevel = CONTROL_CONFIG[:debug_level] || 'INFO'
	puts "Default Log Level: #{loglevel}"

	Control.set_log_level(loglevel)
	Control.start
end
