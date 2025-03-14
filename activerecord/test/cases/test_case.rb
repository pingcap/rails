# frozen_string_literal: true

require "active_support/testing/strict_warnings"
require "active_support"
require "active_support/testing/autorun"
require "active_support/testing/method_call_assertions"
require "active_support/testing/stream"
require "active_record/fixtures"

require "cases/validations_repair_helper"

module ActiveRecord
  # = Active Record Test Case
  #
  # Defines some test assertions to test against SQL queries.
  class TestCase < ActiveSupport::TestCase # :nodoc:
    include ActiveSupport::Testing::MethodCallAssertions
    include ActiveSupport::Testing::Stream
    include ActiveRecord::TestFixtures
    include ActiveRecord::ValidationsRepairHelper

    self.fixture_path = FIXTURES_ROOT
    self.use_instantiated_fixtures = false
    self.use_transactional_tests = ENV["tidb"].present? ? false : true

    def create_fixtures(*fixture_set_names, &block)
      ActiveRecord::FixtureSet.create_fixtures(ActiveRecord::TestCase.fixture_path, fixture_set_names, fixture_class_names, &block)
    end

    def teardown
      SQLCounter.clear_log
    end

    def capture_sql
      ActiveRecord::Base.connection.materialize_transactions
      SQLCounter.clear_log
      yield
      SQLCounter.log.dup
    end

    def assert_sql(*patterns_to_match, &block)
      _assert_nothing_raised_or_warn("assert_sql") { capture_sql(&block) }

      failed_patterns = []
      patterns_to_match.each do |pattern|
        failed_patterns << pattern unless SQLCounter.log_all.any? { |sql| pattern === sql }
      end
      assert failed_patterns.empty?, "Query pattern(s) #{failed_patterns.map(&:inspect).join(', ')} not found.#{SQLCounter.log.size == 0 ? '' : "\nQueries:\n#{SQLCounter.log.join("\n")}"}"
    end

    def assert_queries(num = 1, options = {}, &block)
      ignore_none = options.fetch(:ignore_none) { num == :any }
      ActiveRecord::Base.connection.materialize_transactions
      SQLCounter.clear_log
      x = _assert_nothing_raised_or_warn("assert_queries", &block)
      the_log = ignore_none ? SQLCounter.log_all : SQLCounter.log
      if num == :any
        assert_operator the_log.size, :>=, 1, "1 or more queries expected, but none were executed."
      else
        mesg = "#{the_log.size} instead of #{num} queries were executed.#{the_log.size == 0 ? '' : "\nQueries:\n#{the_log.join("\n")}"}"
        assert_equal num, the_log.size, mesg
      end
      x
    end

    def assert_no_queries(options = {}, &block)
      options.reverse_merge! ignore_none: true
      assert_queries(0, options, &block)
    end

    def assert_column(model, column_name, msg = nil)
      model.reset_column_information
      assert_includes model.column_names, column_name.to_s, msg
    end

    def assert_no_column(model, column_name, msg = nil)
      model.reset_column_information
      assert_not_includes model.column_names, column_name.to_s, msg
    end

    def with_has_many_inversing(model = ActiveRecord::Base)
      old = model.has_many_inversing
      model.has_many_inversing = true
      yield
    ensure
      model.has_many_inversing = old
      if model != ActiveRecord::Base && !old
        model.singleton_class.remove_method(:has_many_inversing) # reset the class_attribute
      end
    end

    def with_automatic_scope_inversing(*reflections)
      old = reflections.map { |reflection| reflection.klass.automatic_scope_inversing }

      reflections.each do |reflection|
        reflection.klass.automatic_scope_inversing = true
        reflection.remove_instance_variable(:@inverse_name) if reflection.instance_variable_defined?(:@inverse_name)
        reflection.remove_instance_variable(:@inverse_of) if reflection.instance_variable_defined?(:@inverse_of)
      end

      yield
    ensure
      reflections.each_with_index do |reflection, i|
        reflection.klass.automatic_scope_inversing = old[i]
        reflection.remove_instance_variable(:@inverse_name) if reflection.instance_variable_defined?(:@inverse_name)
        reflection.remove_instance_variable(:@inverse_of) if reflection.instance_variable_defined?(:@inverse_of)
      end
    end

    def reset_callbacks(klass, kind)
      old_callbacks = {}
      old_callbacks[klass] = klass.send("_#{kind}_callbacks").dup
      klass.subclasses.each do |subclass|
        old_callbacks[subclass] = subclass.send("_#{kind}_callbacks").dup
      end
      yield
    ensure
      klass.send("_#{kind}_callbacks=", old_callbacks[klass])
      klass.subclasses.each do |subclass|
        subclass.send("_#{kind}_callbacks=", old_callbacks[subclass])
      end
    end

    def with_postgresql_datetime_type(type)
      adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      adapter.remove_instance_variable(:@native_database_types) if adapter.instance_variable_defined?(:@native_database_types)
      datetime_type_was = adapter.datetime_type
      adapter.datetime_type = type
      yield
    ensure
      adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      adapter.datetime_type = datetime_type_was
      adapter.remove_instance_variable(:@native_database_types) if adapter.instance_variable_defined?(:@native_database_types)
    end
  end

  class PostgreSQLTestCase < TestCase
    def self.run(*args)
      super if current_adapter?(:PostgreSQLAdapter)
    end
  end

  class Mysql2TestCase < TestCase
    def self.run(*args)
      super if current_adapter?(:Mysql2Adapter)
    end
  end

  class SQLite3TestCase < TestCase
    def self.run(*args)
      super if current_adapter?(:SQLite3Adapter)
    end
  end

  class SQLCounter
    class << self
      attr_accessor :ignored_sql, :log, :log_all
      def clear_log; self.log = []; self.log_all = []; end
    end

    clear_log

    def call(name, start, finish, message_id, values)
      return if values[:cached]

      sql = values[:sql]
      self.class.log_all << sql
      self.class.log << sql unless ["SCHEMA", "TRANSACTION"].include? values[:name]
    end
  end

  ActiveSupport::Notifications.subscribe("sql.active_record", SQLCounter.new)
end
