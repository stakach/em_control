require 'yaml'

settings = YAML::load_file 'settings.yml'
puts settings.inspect
