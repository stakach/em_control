//= require jquery
//= require jquery_ujs
//= require jquery-ui
//= require dashboard/jquery.mousewheel.min
//= require dashboard/jquery.terminal-0.4.3.min
//= require emcontrol



String.prototype.strip = function(char) {
    return this.replace(new RegExp("^" + char + "*"), '').
        replace(new RegExp(char + "*$"), '');
}


$.extend_if_has = function(desc, source, array) {
    for (var i=array.length;i--;) {
        if (typeof source[array[i]] != 'undefined') {
            desc[array[i]] = source[array[i]];
        }
    }
    return desc;
};


(function($) {
    $.fn.tilda = function(eval, options) {
        if ($('body').data('tilda')) {
            return $('body').data('tilda').terminal;
        }
        this.addClass('tilda');
        options = options || {};
        eval = eval || function(command, term) {
            term.echo("you don't set eval for tilda");
        };
        var settings = {
            prompt: '>',
            name: 'tilda',
            height: 200,
            enabled: false,
            greetings: 'Welcome to ACA Control Console. Type "help" for avaliable commands'
        };
        if (options) {
            $.extend(settings, options);
        }
        this.append('<div class="td"></div>');
        var self = this;
        self.terminal = this.find('.td').terminal(eval, settings);
        var focus = false;
        $(document.documentElement).keypress(function(e) {
            if (e.which == 96) {
                self.slideToggle('fast');
                self.terminal.set_command('');
                self.terminal.focus(focus = !focus);
                self.terminal.attr({
                    scrollTop: self.terminal.attr("scrollHeight")
                });
            }
        });
        $('body').data('tilda', this);
        this.hide();
        return self;
    };
})(jQuery);

//--------------------------------------------------------------------------
//



  function get_keys(o) {
    var r = [ ];
    for (var k in o) {
      r.push(k);
    }
    return r;
  }

  function strpad(s, p, len) {
    while (s.length < len) {
      s += p;
    }
    return s;
  }

  function max_length_sa(a) {
    var _l = $.map(a, function(v) {
      return v.length;
    });
    var _mlen = Math.max.apply(Math, _l);
    return _mlen;
  }
		
		
		
	var cmds = {
		help: function() {
			var _cmds = get_keys(cmds);
			var _ml = max_length_sa(_cmds);
			var screen_width = 120;
			var extra = 4;
			var s = "";
			var ret = [ ];
		
			for (var i = 0; i < _cmds.length; ++i) {
				var _s = s + strpad(_cmds[i], ' ', _ml + extra);
				if (_s.length > screen_width) {
					--i;
					ret.push(s);
					s = "";
				} else {
					s = _s;
				}
			}
			if (s.length > 0) {
				ret.push(s);
			}
		
			return ret.join("\n");
		},
		cls: function(terminal){
			terminal.clear();
			return '';
		},
		ls: function(terminal) {
			terminal.pause();
			this.send('ls');
			return '';
		}, 
		"new": function(terminal, system){
			if(!!system) {
				this.send('---GOD---.new_system', system);
				return 'Signal sent...';
			}
			
			return 'The syntax of the command is incorrect.';
		},
		start: function(terminal, system){
			if(!!system) {
				this.send(system + '.start');
				return 'Signal sent...';
			}
			
			return 'The syntax of the command is incorrect.';
		},
		stop: function(terminal, system){
			if(!!system) {
				this.send(system + '.stop');
				return 'Signal sent...';
			}
			
			return 'The syntax of the command is incorrect.';
		},
		'delete': function(terminal, system){
			if(!!system) {
				this.send(system + '.delete');
				return 'Signal sent...';
			}
			
			return 'The syntax of the command is incorrect.';
		},
		reload: function(terminal, system){
			system = parseInt(system);
			
			if(!!system) {
				this.send('---GOD---.reload', system);
				return 'Signal sent...';
			}
			
			return 'The syntax of the command is incorrect.';
		},
		logout: function(terminal){
			terminal.logout();
			return 'You are now logged out.';
		}
	};




//
// Console specific code
//


jQuery(document).ready(function($) {


 function is_non_empty_prefix(p, s) {
    return s.indexOf(p) == 0 && p.length > 0;
  }


  function get_candidates(prefix) {
      var opts = $.grep(get_keys(cmds), function(c) {
        return is_non_empty_prefix(prefix, c);
      });
      return opts;
  }


  function tabcomplete(cmd, pos, terminal, cb) {
    var prefix = jQuery.trim(cmd.substring(0, pos).toLowerCase());
    // console.log("prefix:", prefix);
    var opts = get_candidates(prefix);

    // console.log(prefix, opts);

    if (opts.length == 1 && prefix.length < opts[0].length) {
      var rem = opts[0].substring(prefix.length);
      cb(rem);
    }
    else if (opts.length > 1 && prefix.length < opts[0].length) {
      terminal.echo(opts.join("    "));
    }
    else {
        /* Do Nothing */
    }
  }
  

	var	loggedin = false,
		callback,
		term = $('#tilda'),
		patt = /\w+|"[\w\s]*"/g;
		
	$.Storage.remove('token_tilda', null);
	$.Storage.remove('login_tilda', null);
	
	var con = new acaControl.EventsDispatcher({
		system: 0
	});
	con.bind({
		authenticate:function() {
			callback(false);
		},
		ready: function() {
			loggedin = true;
			callback(true);
		},
		close: function() {
			if(loggedin) {
				term.terminal.error('Disconnected from control server');
				term.terminal.logout();
			}
		},
		ls: function(data) {
			term.terminal.echo(data.names.join(', '));
			term.terminal.resume();
		}
	});

	term.tilda(function(command, terminal) {
		var clc = jQuery.trim(command);
		var clcs = clc.match(patt);
		
		if (clc.length == 0) {
			terminal.echo("");
			return;
		}
		
		//
		// Remove any inverted commas from the commands
		//
		if(clcs.length > 1) {
			var i;
			for(i=1; i < clcs.length; i++){
				clcs[i] = clcs[i].split('"').join('');
			}
		}
		
		var clc0 = clcs[0];
		var opts = get_candidates(clc0);
		
		clcs[0] = terminal;

		if (opts.length == 1) {
			//terminal.echo(cmds[opts[0]](clc));
			terminal.echo(cmds[opts[0]].apply( con, clcs));
		}
		else if (opts.length > 1) {
			var s = "Choose one of: " + opts.join(", ");
			terminal.echo(s);
		}
		else {
			terminal.echo("terminal: " + command + ": command not found");
		}
	}, {
		login: function(login, password, thecallback){
			callback = thecallback;
			
			if(con.is_connected()){

				var username = login.split('\\'),
					domain = username[0];
				username = username[1];
    			
				con.send("authenticate", username, password, domain);
			} else {
				callback(false);
				term.terminal.error('Not connected to the control server');
			}
		}
	});
});
