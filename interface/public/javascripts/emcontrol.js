/*
	emcontrol HTML5 interface usage:

// bind to server events
socket.bind('some_event', function(data){
alert(data.name + ' says: ' + data.message)
});

// broadcast events to all connected users
socket.send( 'some_event', {name: 'ismael', message : 'Hello world'} );
*/
var Off = false;
var On = true;

var EventsDispatcher = function (url, calls) {
	var conn = null;
	var the_url = url;
	var callbacks = {};
	var connected = true; // This is for disconnect trigger in conn.onclose
	var ready = false;
	var polling = null;

	var system_calls = {
		open: function () { },
		close: function () { },
		ls: function () { },
		ready: function () { },
		authenticate: function () { },
		system: function () { }
	};
	$.extend(system_calls, calls);


	var update = function (calls) {
		if (!(calls instanceof Object))
			return;
		$.extend(system_calls, calls);
	}

	var send = function (command_name, arguments) {
		if (arguments === undefined) {
			arguments = [];
		}
		if (!(arguments instanceof Array)) {
			arguments = [arguments];
		}

		var payload = JSON.stringify({ command: command_name, data: arguments });
		//$("#msg").append("<p>Payload:" + payload + "</p>");

		if (conn.readyState == conn.OPEN)
			conn.send(payload); // <= send JSON data to socket server

		return this;
	};

	this.send = send;

	this.bind = function (event_name, callback) {
		callbacks[event_name] = callbacks[event_name] || [];
		callbacks[event_name].push(callback);

		if (conn.readyState == conn.OPEN)
			send("register", event_name.split('.'));

		return this; // chainable
	};

	var dispatch = function (event_name, message) {
		var chain = callbacks[event_name];
		if (chain === undefined) return; // no callbacks for this event
		for (var i = 0; i < chain.length; i++) {
			try {
				chain[i](message);
			} catch (err) { } // Catch any user code errors
		}
	}

	//
	// TODO:: implement unbind!!
	//
	function setup_connection() {
		conn = new WebSocket(the_url);

		// dispatch to the right handlers
		conn.onmessage = function (evt) {
			var json = JSON.parse(evt.data);

			if (system_calls[json.event] === undefined) {
				dispatch(json.event, json.data);
				return; // non-system event
			}
			else if (json.event == "ready") {

				//
				// Re-register status events then call ready
				//
				polling = setInterval("send('ping')", 60000); // Maintain the connection by pinging every 1min
				try {
					for (event_name in callbacks) {
						send("register", event_name.split('.'));
					}
				} catch (err) { } // Catch any send errors incase we disconnect

			}

			system_calls[json.event](); // System event
		};

		conn.onclose = function () {
			if (connected) {
				connected = false;
				clearInterval(polling);
				system_calls.close();
			}
			setup_connection();
		}
		conn.onopen = function () {
			connected = true; // prevent multiple disconnect triggers
			system_calls.open();
		}
	}
	setup_connection();
};
