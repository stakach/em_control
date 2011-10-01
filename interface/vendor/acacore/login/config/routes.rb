Rails.application.routes.draw do
	
	# You can have the root of your site routed with "root"
	# just remember to delete public/index.html.
	# root :to => 'welcome#index'
	root :to => "authentication#start"
	post 'login' => 'authentication#login'
	get 'logout' => 'authentication#logout'
	post 'edit' => 'authentication#edit'
	post 'update' => 'authentication#update'
	
end
