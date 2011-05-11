ENV['RAILS_ENV'] = ARGV.first || ENV['RAILS_ENV'] || 'development'  
require File.expand_path(File.dirname(__FILE__) + "/interface/config/environment")

loglevel = 'INFO'

if ARGV.length > 1
	loglevel = ARGV[1]
end

require './em-control.rb'

puts "Default Log Level: #{loglevel}"

Control.set_log_level(loglevel)
Control.start
