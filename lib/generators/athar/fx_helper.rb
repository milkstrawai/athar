# frozen_string_literal: true

require "fx"

module Athar
  module Generators
    module FxHelper
      def self.included(base)
        base.class_option :fx,
                          type: :boolean,
                          optional: true,
                          desc: "Use the fx gem to manage SQL functions and triggers (default when fx is loaded)."
      end

      def fx?
        return true if options[:fx] == true
        return false if options[:fx] == false

        defined?(::Fx::SchemaDumper) ? true : false
      end

      def schema_format
        return :ruby unless Rails.application

        Rails.application.config.active_record.schema_format || :ruby
      end

      def ensure_raw_sql_supported!
        return if schema_format == :sql

        raise ::Thor::Error,
              "Athar requires the fx gem (default) or `config.active_record.schema_format = :sql` " \
              "when using --no-fx. Either install fx or switch the host app to SQL schema dumps."
      end

      # Indent each non-blank line of `text` by `spaces` spaces.
      def indent_sql(text, spaces)
        prefix = " " * spaces
        text.each_line.map { |line| line.strip.empty? ? line : prefix + line }.join
      end

      # Resolve the app-wide Rails generator primary/foreign-key types.
      def athar_primary_key_type
        primary_key_setting || :primary_key
      end

      def athar_foreign_key_type
        primary_key_setting || :bigint
      end

      def primary_key_setting
        return nil unless defined?(::Rails) && ::Rails.respond_to?(:configuration)

        generators_config = ::Rails.configuration.generators
        orm = generators_config.orm
        generators_config.options[orm][:primary_key_type]
      end
    end
  end
end
