desc 'Start the control system server'
task :control, :debug, :needs => :environment do |t, args|
	args.with_defaults(:debug => 'INFO')

	require './../em-control.rb'

	puts "Default Log Level: #{args[:debug]}"

	Control.set_log_level(args[:debug])
	Control.start
end
