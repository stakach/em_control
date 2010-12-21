/*
	emcontrol HTML5 interface usage:

// bind to server events
socket.bind('some_event', function(data){
alert(data.name + ' says: ' + data.message)
});

// broadcast events to all connected users
socket.send( 'some_event', {name: 'ismael', message : 'Hello world'} );
*/


var EventsDispatcher = function (url, system_name) {
	var conn = new WebSocket(url);
	var system = system_name;
	var callbacks = {};

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

	this.bind = function (event_name, callback) {
		callbacks[event_name] = callbacks[event_name] || [];
		callbacks[event_name].push(callback);

		if (conn.readyState == conn.OPEN && event_name != "open" && event_name != "close")
			send("register", event_name.split('.'));

		return this; // chainable
	};

	this.send = send;

	// dispatch to the right handlers
	conn.onmessage = function (evt) {
		var json = JSON.parse(evt.data);
		dispatch(json.event, json.data);
	};

	conn.onclose = function () { dispatch('close', null); }
	conn.onopen = function () {
		send("system", [system]);

		dispatch('open', null);

		//
		// Re-register status events
		//
		try {
			for (event_name in callbacks) {
				if (event_name != 'close' && event_name != 'open') {
					send("register", event_name.split('.'));
				}
			}
		} catch (err) { } // Catch any send errors incase we disconnect
	}

	var dispatch = function (event_name, message) {
		var chain = callbacks[event_name];
		if (typeof chain == 'undefined') return; // no callbacks for this event
		for (var i = 0; i < chain.length; i++) {
			try {
				chain[i](message);
			} catch (err) { } // Catch any user code errors
		}
	}

	//
	// TODO:: implement unbind!!
	//
};
