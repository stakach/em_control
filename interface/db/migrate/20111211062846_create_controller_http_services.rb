class CreateControllerHttpServices < ActiveRecord::Migration
  def change
    create_table :controller_http_services do |t|

      t.timestamps
    end
  end
end
