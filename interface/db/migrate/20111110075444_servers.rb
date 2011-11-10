class Servers < ActiveRecord::Migration
	def up
		create_table :servers do |t|
			t.boolean	:online,	:allow_null => false, :default => true
			
			t.string	:hostname,	:allow_null => false
			
			t.text		:notes
		end
	end

	def down
		#drop table
	end
end
