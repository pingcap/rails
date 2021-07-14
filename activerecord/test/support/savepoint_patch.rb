require 'active_record/connection_adapters/mysql2_adapter'
ActiveRecord::ConnectionAdapters::Mysql2Adapter.class_eval do 
  def supports_savepoints?
    false
  end

  def supports_foreign_keys?
    false
  end

  def supports_bulk_alter?
    false
  end

  def supports_advisory_locks?
    false
  end

  def supports_optimizer_hints?
    false
  end
end