//= require jquery

$(document).ready(function(){
	var $input = $('input[name="username"]');
	if($input.val() == "")
		$input.focus();
	else
		$('input[name="password"]').focus();
});

if(!!history.pushState)
	history.pushState({}, document.title, '/');
