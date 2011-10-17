class Setting < ActiveRecord::Base
	belongs_to :object, :polymorphic => true
	
	
	protected
	
	
	validates_presence_of :name, :object, :value_type
end
