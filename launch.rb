ENV['RAILS_ENV'] = ARGV.first || ENV['RAILS_ENV'] || 'development'  
require File.expand_path(File.dirname(__FILE__) + "/interface/config/environment")

loglevel = CONTROL_CONFIG[:debug_level] || 'INFO'
require './em-control.rb'

puts "Default Log Level: #{loglevel}"

Control.set_log_level(loglevel)
Control.start
