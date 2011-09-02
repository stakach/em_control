//= require jquery

$(document).ready(function(){
	$('table tr:first-child input').focus();
});

if(!!history.pushState)
	history.pushState({}, document.title, '/');
