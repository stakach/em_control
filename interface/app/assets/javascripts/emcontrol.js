/**
*	ACA Control jQuery Interface Library
*	Simplifies communication with an ACA Control server when using jQuery
*	
*   Copyright (c) 2011 Advanced Control and Acoustics.
*	
*	@author 	Stephen von Takach <steve@advancedcontrol.com.au>
* 	@copyright  2011 advancedcontrol.com.au
*
*	--- Usage ---
*	Connecting to an ACA Control Server:
		var controller = new acaControl.EventsDispatcher({
			url: 'http://my.control.server.org:8080/',
			one_time_key: '/key/url'
		});

*	Binding to an event:
		controller.bind('some_event', function(data){
			alert(data.name + ' says: ' + data.message)
		});

*	Sending a command to the server:
		controller.send('Module.function', "item1", ['item', 2], {item:3}, 4, 5.0, ...);

*
**/





var acaControl = {
	Off: false,
	On: true,
	Controllers: [],	// So we can inspect all instances
	EventsDispatcher: function (options) {
		//
		// options contains: url, system calls, system
		//
		var config = {
			url: null,			// URL of the ACA Control Server
			system: null,		// The system we are connecting to and authentication details for re-connects
			auto_auth: null		// Are we using the manifest authentication system
		},
			state ={
				connection: null,	// Base web socket
			    connected: true,	// Are we currently connected (initialised to true so that any initial failure is triggered)
			    ready: false,		// Is the server ready for bindings and commands
			    polling: false,		// Are we polling to remain connected when there is little activity
			    resume: false		// The reference to the resume timer
			},
		    bindings = {},
		    system_calls = {
				open: true,			// Connection to the server has been made
				close: true,		// Connection to the server was closed or lost
				ls: true,			// List of control systems available to the current user (paginated)
				ready: true,		// Remote System is ready for bindings
				authenticate: true,	// Authentication required
				system: true,		// Please select a system
				pong: true			// System is idle
			},
			$this = this;
		$.extend(config, options);
		this.config = config;					// Allow external access
		
		
		//
		// Sends a command to the server in the appropriate format
		//
		var send = function (command_name) {
			var payload = JSON.stringify({ command: command_name, data: Array.prototype.slice.call( arguments, 1 ) });
			//	Array.prototype.slice.call( arguments, 1 ) gets all the arguments - the first in an array
	
			if (state.connection.readyState == state.connection.OPEN) {
				state.connection.send(payload); // <= send JSON data to socket server
				set_poll();						// Reset polling
			}
	
			return $this; // chainable
		};
		this.send = send;
		
		//
		// Requests to recieve notifications of a value change from the server
		//	Triggers the functions passed in when the server informs us of an update
		//
		this.bind = function (events, func) {
			if(!!func) {
				var temp = {};
				temp[events] = func;
				events = temp;
			}
			
			jQuery.each( events, function(event_name, callback){
				bindings[event_name] = bindings[event_name] || [];
				bindings[event_name].push(callback);
				
				if (!system_calls[event_name] && state.connection.readyState == state.connection.OPEN){
					var args = event_name.split('.');
					args.splice(0,0, 'register');
					send.apply( this, args );
				}
			});
			
			return this; // chainable
		};
		
		//
		// Removes all the callbacks for the event and lets the server know that we
		//	don't want to revieve it anymore.
		//
		this.unbind = function (event_name) {
			delete bindings[event_name];
			
			if (state.connection.readyState == state.connection.OPEN){
				var args = event_name.split('.');
				args.splice(0,0, 'unregister');
				send.apply( this, args );
			}
			
			return this; // chainable
		};
		
		//
		// The event trigger, calls the registered handlers in order
		//
		var trigger = function (event_name, message) {
			var chain = bindings[event_name];
			if (chain === undefined) return; // no bindings for this event
			
			var i, result;
			for (i = 0; i < chain.length; i = i + 1) {
				try {
					result = chain[i](message);
					if(result === false)	// Return false to prevent later bindings
						break;
				} catch (err) { } // Catch any user code errors
			}
			
			return $this; // chainable
		};
		this.trigger = trigger;
		
		
		//
		// Polling functions
		//	Only called if no other traffic is being transmitted.
		//
		function set_poll(){
			if(!!state.polling) {
				clearInterval(state.polling);
			}
			state.polling = setInterval(do_poll, 60000); // Maintain the connection by pinging every 1min
		}
		
		function do_poll(){
			send('ping');
		}
		
		
		//
		// Sets up a new connection to the remote server
		//
		function setup_connection() {
			state.connection = new WebSocket(config.url); // This will fail completely if an iphone is put to sleep
	
			// dispatch to the right handlers
			state.connection.onmessage = function (evt) {
				var json = JSON.parse(evt.data);
				
				if (json.event == 'ready') {
					//
					// Re-register status events then call ready
					//
					for (event_name in bindings) {
						try {
							if(!system_calls[event_name]) {
								var args = event_name.split('.');
								args.splice(0,0, 'register');
								send.apply( this, args );
							}
						} catch (err) { }
					}
					
					set_poll();	// Set the polling to occur
				}
				
				//
				// Trigger callbacks
				//
				trigger(json.event, json.data);
			};
			
			state.connection.onclose = function () {
				if (state.connected) {
					state.connected = false;
					if(!!state.polling) {
						clearInterval(state.polling);
						state.polling = false;
					}
					trigger('close');
				}
			}
			state.connection.onopen = function () {
				state.connected = true; // prevent multiple disconnect triggers
				trigger('open');
			}
		}
		setup_connection();
		
		
		//
		// Ensure the connection is resumed if disconnected
		//	We do this in this way for mobile devices when resumed from sleep to ensure they reconnect
		//
		function checkResume() {
			if (state.connection.readyState == state.connection.CLOSED) {
				setup_connection();
			}
		}
		state.resume = window.setInterval(checkResume, 1000);
		acaControl.Controllers.push(this);
		
		
		//
		// Bind events for automation (first attempt, else fall back to interface for both auth and system)
		//
		var appCache = window.applicationCache,
			authCount = 0,
			keyAuthed = false,
			oneKey;
			
		this.bind('authenticate', function(){
			authCount += 1;
			
			if(authCount == 1 && (!!config.auto_auth) && (!!config.system)) {
				jQuery.ajax('/tokens/key', {
					type: 'GET',
					dataType: 'text',
					success: function(data, textStatus, jqXHR){
						oneKey = data;
						send("authenticate", oneKey);
					},
					error: function(){
						keyAuthed = true;	// allow the external system to update the cache
						send("authenticate", 'failed');		// Triggers the user interface
					}
				});
				
				return false;
			}
		});
		
		var sysCallCount = 0;
		this.bind('system', function(){
			sysCallCount += 1;
			
			if(sysCallCount == 1 && (!!config.system)) {
				controller.send("system", config.system);
				
				return false;
			}	// Auto login failure here will result in a disconnect
		});
		
		this.bind('ready', function(){
			if((!!config.auto_auth) && (!!config.system) && sysCallCount == 1 && authCount == 1) {
				//
				// Authenticate with the server
				// Then we can safely reload the cache
				// on cache success we accept the new key
				//
				jQuery.ajax('/tokens/authenticate', {
					type: 'POST',
					data: {
						key: oneKey,
						system: config.system
					},
					dataType: 'text',
					success: function(data, textStatus, jqXHR){
						// trigger manifest update
						// Then call accept (from manifest event)
						keyAuthed = true;
						appCache.update();
						
					},
					error: function(){
						//
						// This can safely be ignored. Here for debugging
						//
						var damn = "fail";
					}
				});
			}
			
			authCount = 0;
			sysCallCount = 0;
			oneKey = null;
		});
		
		
		function bindCache(){
			$(appCache).bind('checking', function(){
				if(!!keyAuthed){
					appCache.abort();
					return false;
				}
			});
			
			$(appCache).bind('updateready', function(){
				appCache.swapCache();	// Swap cache has called key
				appCache = window.applicationCache;
				bindCache();
				
				jQuery.ajax('/tokens/accept', {
					type: 'POST',
					data: {
						key: oneKey,
						system: config.system
					},
					dataType: 'text',
					success: function(data, textStatus, jqXHR){
						//
						// This can safely be ignored. Here for debugging
						//
						var yay = "success";
					},
					error: function(){
						//
						// This can safely be ignored. Here for debugging
						//
						var damn = "fail";
					}
				});
			});
		}
		
		if((!!config.auto_auth) && (!!config.system)) {
			bindCache();
		}
		
		//
		// Disconnects and removes the self reference to the object
		//	Once all external references are removed it will be garbage collected
		//
		this.destroy = function(){
			clearInterval(state.resume);
			state.connection.close();
			var i;
			for(i = 0; i < acaControl.Controllers.length; i = i + 1) {
				if(acaControl.Controllers[i] == this) {
					acaControl.Controllers.splice(i, 1);
					break;
				}
			}
		};
	}
};
