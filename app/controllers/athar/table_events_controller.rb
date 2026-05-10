# frozen_string_literal: true

module Athar
  class TableEventsController < ApplicationController
    def show
      @event = Athar::TableEvent.find_by(id: params[:id])

      head(:not_found) and return unless @event
    end
  end
end
