class Notifier < ActionMailer::Base
	default from: "projects@advancedcontrol.com.au"
	
	def alert(system, subject, message)
		@sys_name = system.controller.name
		@message = message
		@subject = subject
		mail(:to => system.controller.users.where('users.system_admin = ?', true).all.map(&:email), :subject => subject)
	end
	
	def notify(system, subject, message)
		@sys_name = system.controller.name
		@message = message
		@subject = subject
		mail(:to => system.controller.users.where('users.system_admin = ?', true).all.map(&:email), :subject => subject)
	end
end
