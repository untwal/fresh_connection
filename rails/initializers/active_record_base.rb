module ActiveRecord
  module ConnectionAdapters
    class AbstractAdapter
      def select_all_with_slave_cluster(*args)
        if FreshConnection::SlaveConnection.slave_access?
          change_connection {select_all_without_slave_cluster(*args)}
        else
          select_all_without_slave_cluster(*args)
        end
      end
      alias_method_chain :select_all, :slave_cluster

      def columns_with_slave_cluster(*args)
        if FreshConnection::SlaveConnection.slave_access?
          change_connection {columns_without_slave_cluster(*args)}
        else
          columns_without_slave_cluster(*args)
        end
      end
      alias_method_chain :columns, :slave_cluster

      def log_info_with_slave_cluster(sql, name, ms)
        name = "[MASTER] " + (name || "SQL") if !FreshConnection::SlaveConnection.slave_access? && name != "CACHE"
        log_info_without_slave_cluster(sql, name, ms)
      end
      alias_method_chain :log_info, :slave_cluster

      private

      def change_connection
        master_con, @connection = @connection, FreshConnection::SlaveConnection.connection.raw_connection
        yield
      ensure
        @connection = master_con
      end
    end

    class MysqlAdapter < AbstractAdapter
      private

      def configure_connection_with_ignore
        configure_connection_without_ignore unless FreshConnection::SlaveConnection.ignore_configure_connection?
      end
      alias_method_chain :configure_connection, :ignore
    end
  end

  class Base
    class << self
      def find_every_with_slave_cluster(options)
        run_on_db(options) { find_every_without_slave_cluster(options) }
      end
      alias_method_chain :find_every, :slave_cluster

      def find_by_sql_with_slave_cluster(sql, options = nil)
        run_on_db(options) { find_by_sql_without_slave_cluster(sql) }
      end
      alias_method_chain :find_by_sql, :slave_cluster

      def count_by_sql_with_slave_cluster(sql, options = nil)
        run_on_db(options) { count_by_sql_without_slave_cluster(sql) }
      end
      alias_method_chain :count_by_sql, :slave_cluster

      def calculate_with_slave_cluster(operation, column_name, options = {})
        run_on_db(options) do
          options.delete(:readonly)
          calculate_without_slave_cluster(operation, column_name, options)
        end
      end
      alias_method_chain :calculate, :slave_cluster

      private

      def run_on_db(options)
        in_run_on_db(options)
        run_on_db_status[:go_slave] ? run_on_readonly_db{yield} : yield
      ensure
        out_run_on_db
      end

      def in_run_on_db(options)
        run_on_db_status[:go_slave] = go_slave?(options) if run_on_db_status[:count] == 0
        run_on_db_status[:count] += 1
      end

      def out_run_on_db
        run_on_db_status[:count] -= 1
      end

      def run_on_db_status
        Thread.current[:run_on_db_status] ||= {:count => 0, :go_slave => false}
      end

      def go_slave?(options)
        !FreshConnection::SlaveConnection.ignore_model?(self.name) && connection.open_transactions == 0 &&
          (!options.is_a?(Hash) || !options.key?(:readonly) || options[:readonly].nil? || options[:readonly])
      end

      def run_on_readonly_db
        FreshConnection::SlaveConnection.slave_access_in
        yield
      ensure
        FreshConnection::SlaveConnection.slave_access_out
      end
    end
  end
end

