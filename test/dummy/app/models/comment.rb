# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
end
