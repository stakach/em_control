require 'rubygems'
require 'eventmachine'


#
# Echo server - fail constantly on a single command and test serialisation
#		Fail on another command once to test retry functions
#


  module EchoServer
    def post_init
      puts "-- someone connected to the echo server!"
    end

	@@failonce=true

     def initialize(*args)
      super
      
	
    end
     
    def receive_data(data)
      p data
	if data == "critical ping"
      		send_data 'fail'
	elsif (data == "criticalish ping") && @@failonce
		@@failonce = false
		send_data 'fail'
	else
		send_data data
	end
    end

    def unbind
      p ' connection totally closed'
    end
  end

  EventMachine::run {
    EventMachine::start_server "127.0.0.1", 8081, EchoServer
    puts 'running echo server on 8081'
  }
