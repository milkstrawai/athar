# frozen_string_literal: true

require "erb"

module Athar
  module SQL
    GENERATORS_ROOT = File.expand_path("../generators/athar", __dir__)

    INSTALL_FUNCTIONS_DIR = File.join(GENERATORS_ROOT, "install", "functions")
    MODEL_TRIGGERS_DIR = File.join(GENERATORS_ROOT, "model", "triggers")

    STATIC_FUNCTIONS = %w[
      athar_filter_keys
      athar_capture_delete
    ].freeze

    TEMPLATE_FUNCTIONS = %w[
      athar_capture_truncate
    ].freeze

    INSTALLED_FUNCTIONS = (STATIC_FUNCTIONS + TEMPLATE_FUNCTIONS).freeze

    class << self
      def read_function(name, locals = {})
        if STATIC_FUNCTIONS.include?(name)
          File.read(File.join(INSTALL_FUNCTIONS_DIR, "#{name}.sql"))
        elsif TEMPLATE_FUNCTIONS.include?(name)
          path = File.join(INSTALL_FUNCTIONS_DIR, "#{name}.sql.erb")
          render(File.read(path), locals)
        else
          raise ArgumentError, "unknown SQL function: #{name.inspect}"
        end
      end

      def all_functions(locals = {})
        INSTALLED_FUNCTIONS.to_h { |name| [name, read_function(name, locals)] }
      end

      def function_signature(name)
        case name
        when "athar_filter_keys" then "jsonb, text[]"
        when "athar_capture_delete", "athar_capture_truncate" then ""
        else
          raise ArgumentError, "unknown SQL function: #{name.inspect}"
        end
      end

      def render(template, locals)
        Render.new(locals).result(template)
      end
    end

    class Render
      def initialize(locals)
        @locals = locals
      end

      def result(template)
        binding_context = binding
        @locals.each do |key, value|
          binding_context.local_variable_set(key, value)
        end
        ERB.new(template, trim_mode: "-").result(binding_context)
      end
    end
  end
end
