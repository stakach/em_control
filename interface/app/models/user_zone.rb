class UserZone < ActiveRecord::Base
	belongs_to	:zone
	belongs_to	:group
	
	
	protected
	
	
	validates_presence_of :group, :zone
end
