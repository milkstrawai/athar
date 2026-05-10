# frozen_string_literal: true

module Athar
  class ApplicationController < ::ApplicationController
    layout "athar/application"

    helper Athar::DashboardHelper
    helper Athar::AssetHelper
  end
end
