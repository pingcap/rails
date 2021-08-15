# frozen_string_literal: true

require "global_id/railtie"
require "active_job"

module ActiveJob
  # = Active Job Railtie
  class Railtie < Rails::Railtie # :nodoc:
    config.active_job = ActiveSupport::OrderedOptions.new
    config.active_job.custom_serializers = []

    initializer "active_job.logger" do
      ActiveSupport.on_load(:active_job) { self.logger = ::Rails.logger }
    end

    initializer "active_job.custom_serializers" do |app|
      config.after_initialize do
        custom_serializers = app.config.active_job.delete(:custom_serializers)
        ActiveJob::Serializers.add_serializers custom_serializers
      end
    end

    initializer "active_job.set_configs" do |app|
      options = app.config.active_job
      options.queue_adapter ||= :async

      ActiveSupport.on_load(:active_job) do
        options.each do  |k, v|
          k = "#{k}="
          send(k, v) if respond_to? k
        end
      end

      ActiveSupport.on_load(:action_dispatch_integration_test) do
        include ActiveJob::TestHelper
      end

      ActiveSupport.on_load(:active_record) do
        self.destroy_association_async_job = ActiveRecord::DestroyAssociationAsyncJob
      end
    end

    initializer "active_job.set_reloader_hook" do |app|
      ActiveSupport.on_load(:active_job) do
        ActiveJob::Callbacks.singleton_class.set_callback(:execute, :around, prepend: true) do |_, inner|
          app.reloader.wrap do
            inner.call
          end
        end
      end
    end

    initializer "active_job.query_log_tags" do |app|
      ActiveSupport.on_load(:active_job) do
        singleton_class.attr_accessor :log_query_tags_around_perform
        self.log_query_tags_around_perform = true
      end

      ActiveSupport.on_load(:active_record) do
        if app.config.active_record.query_log_tags_enabled && app.config.active_job.log_query_tags_around_perform != false
          ActiveRecord::QueryLogs.taggings[:job] = -> { context[:job]&.class&.name }
          ActiveRecord::QueryLogs.tags << :job

          ActiveJob::Base.class_eval do
            around_perform :expose_job_to_query_logs

            private
              def expose_job_to_query_logs(&block)
                ActiveRecord::QueryLogs.set_context(job: self, &block)
              end
          end
        end
      end
    end
  end
end
