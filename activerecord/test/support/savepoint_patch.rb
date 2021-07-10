require 'active_record/connection_adapters/mysql2_adapter'
ActiveRecord::ConnectionAdapters::Mysql2Adapter.class_eval do 
  def supports_savepoints?
    false
  end
end