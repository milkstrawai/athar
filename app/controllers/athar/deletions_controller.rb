# frozen_string_literal: true

module Athar
  class DeletionsController < ApplicationController
    def show
      @deletion = Athar::Deletion.find_by(id: params[:id])

      head(:not_found) and return unless @deletion

      @registry = Athar::Dashboard::ModelRegistry.discover
      @registry_by_id = @registry.index_by { |model| [model.schema, model.table] }
    end
  end
end
